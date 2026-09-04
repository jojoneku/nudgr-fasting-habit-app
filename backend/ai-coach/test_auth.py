"""Tests for the streaming advisor's token verification.

This is the whole security boundary for the advisor's Function URL, which runs
with AuthType NONE — everything past `verify_supabase_token` is reachable by
anyone on the internet who can form a POST. So these tests are written as
attacks rather than as happy paths: each one is a way in that must stay closed.

Run from backend/ai-coach/:
    BEDROCK_MODEL_ID=x SUPABASE_URL=https://p.supabase.co \\
    SUPABASE_ANON_KEY=k python -m pytest test_auth.py -q

No AWS or Supabase access needed — the key set is stubbed and every token is
minted locally.
"""

import json
import time

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec, rsa

import lambda_function as lf

ISSUER = "https://p.supabase.co/auth/v1"


def _rsa_key():
    return rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _jwk(private_key, kid):
    """The public half, in the shape Supabase's JWKS endpoint serves."""
    pub = private_key.public_key()
    data = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(pub))
    data["kid"] = kid
    data["alg"] = "RS256"
    data["use"] = "sig"
    return data


def _token(private_key, *, kid="k1", alg="RS256", **claims):
    payload = {
        "sub": "user-123",
        "iss": ISSUER,
        "exp": int(time.time()) + 3600,
        **claims,
    }
    return jwt.encode(payload, private_key, algorithm=alg,
                      headers={"kid": kid})


@pytest.fixture(autouse=True)
def _stub_jwks(monkeypatch):
    """Serve one known key, and count fetches so caching can be asserted."""
    key = _rsa_key()
    calls = {"n": 0}

    def fake_fetch(force=False):
        calls["n"] += 1
        return [_jwk(key, "k1")]

    monkeypatch.setattr(lf, "_fetch_jwks", fake_fetch)
    monkeypatch.setattr(lf, "_SUPABASE_URL", "https://p.supabase.co")
    monkeypatch.setattr(lf, "_SUPABASE_ANON_KEY", "anon-key")
    return {"key": key, "calls": calls}


# ── The one case that must succeed ───────────────────────────────────────────

def test_a_valid_token_is_accepted(_stub_jwks):
    claims = lf.verify_supabase_token(_token(_stub_jwks["key"]))
    assert claims["sub"] == "user-123"


# ── Ways in that must stay closed ────────────────────────────────────────────

def test_no_token_is_rejected():
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token("")
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(None)


def test_garbage_is_rejected():
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token("not-a-jwt")
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token("a.b.c")


def test_an_expired_token_is_rejected(_stub_jwks):
    stale = _token(_stub_jwks["key"], exp=int(time.time()) - 60)
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(stale)


def test_a_token_signed_by_a_foreign_key_is_rejected(_stub_jwks):
    # Correct shape, correct kid, correct issuer — signed by someone else. This
    # is the attack the signature check exists for.
    attacker = _rsa_key()
    forged = _token(attacker, kid="k1")
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(forged)


def test_an_unknown_kid_is_rejected(_stub_jwks):
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(_token(_stub_jwks["key"], kid="who-dis"))


def test_alg_none_is_rejected(_stub_jwks):
    # The classic JWT bypass: drop the signature and claim it was never needed.
    unsigned = jwt.encode(
        {"sub": "user-123", "iss": ISSUER, "exp": int(time.time()) + 3600},
        key=None, algorithm="none", headers={"kid": "k1"})
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(unsigned)


def test_a_symmetric_algorithm_is_rejected(_stub_jwks):
    # HS256 verified against a PUBLIC key would let any caller sign their own
    # token with a value they can simply read off the JWKS endpoint.
    forged = jwt.encode(
        {"sub": "user-123", "iss": ISSUER, "exp": int(time.time()) + 3600},
        key="anything", algorithm="HS256", headers={"kid": "k1"})
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(forged)


def test_another_projects_issuer_is_rejected(_stub_jwks):
    other = _token(_stub_jwks["key"], iss="https://someone-else.supabase.co/auth/v1")
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(other)


def test_a_token_with_no_subject_is_rejected(_stub_jwks):
    # sub is the rate-limit identity; without one a caller would be
    # unattributable and effectively uncapped.
    anon = jwt.encode(
        {"iss": ISSUER, "exp": int(time.time()) + 3600},
        _stub_jwks["key"], algorithm="RS256", headers={"kid": "k1"})
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(anon)


def test_a_token_with_no_expiry_is_rejected(_stub_jwks):
    forever = jwt.encode(
        {"sub": "user-123", "iss": ISSUER},
        _stub_jwks["key"], algorithm="RS256", headers={"kid": "k1"})
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(forever)


def test_an_unconfigured_deployment_refuses_rather_than_failing_open(
        monkeypatch, _stub_jwks):
    # Behind AuthType NONE, failing open on missing config would publish a
    # Bedrock endpoint to the internet.
    monkeypatch.setattr(lf, "_SUPABASE_URL", "")
    with pytest.raises(lf.AuthError):
        lf.verify_supabase_token(_token(_stub_jwks["key"]))


# ── Header parsing ───────────────────────────────────────────────────────────

def test_bearer_token_extraction():
    assert lf.bearer_token_from_headers({"authorization": "Bearer abc"}) == "abc"
    # API Gateway lowercases; a Function URL may not.
    assert lf.bearer_token_from_headers({"Authorization": "Bearer abc"}) == "abc"
    assert lf.bearer_token_from_headers({"authorization": "bearer abc"}) == "abc"
    assert lf.bearer_token_from_headers({"authorization": "abc"}) == ""
    assert lf.bearer_token_from_headers({}) == ""
    assert lf.bearer_token_from_headers(None) == ""


# ── The gateway path must be untouched ───────────────────────────────────────

def test_gateway_authorizer_claims_still_win():
    event = {
        "requestContext": {
            "authorizer": {"jwt": {"claims": {"sub": "gw-user"}}}
        }
    }
    assert lf._get_user_id(event) == "gw-user"


def test_get_user_id_returns_none_without_an_authorizer():
    assert lf._get_user_id({}) is None
    assert lf._get_user_id({"requestContext": {}}) is None


# ── Key rotation ─────────────────────────────────────────────────────────────

def test_an_unknown_kid_triggers_exactly_one_refetch(monkeypatch):
    # A rotated key is indistinguishable from a bogus one, so it refetches once
    # before rejecting — otherwise a rotation signs every user out.
    key = _rsa_key()
    calls = {"n": 0}

    def fake_fetch(force=False):
        calls["n"] += 1
        # Serve the real key only on the forced refetch.
        return [_jwk(key, "k2")] if force else [_jwk(key, "k1")]

    monkeypatch.setattr(lf, "_fetch_jwks", fake_fetch)
    monkeypatch.setattr(lf, "_SUPABASE_URL", "https://p.supabase.co")
    monkeypatch.setattr(lf, "_SUPABASE_ANON_KEY", "anon-key")

    claims = lf.verify_supabase_token(_token(key, kid="k2"))
    assert claims["sub"] == "user-123"
    assert calls["n"] == 2, "should refetch once, not on every call"


def test_an_ecc_token_is_accepted_if_the_key_set_serves_one():
    # Supabase is on RS256 today, but ES256 is a legitimate asymmetric choice
    # and must not be rejected as if it were symmetric.
    key = ec.generate_private_key(ec.SECP256R1())
    pub_jwk = json.loads(jwt.algorithms.ECAlgorithm.to_jwk(key.public_key()))
    pub_jwk.update({"kid": "e1", "alg": "ES256", "use": "sig"})

    import unittest.mock as mock
    with mock.patch.object(lf, "_fetch_jwks", lambda force=False: [pub_jwk]), \
         mock.patch.object(lf, "_SUPABASE_URL", "https://p.supabase.co"), \
         mock.patch.object(lf, "_SUPABASE_ANON_KEY", "anon-key"):
        token = _token(key, kid="e1", alg="ES256")
        assert lf.verify_supabase_token(token)["sub"] == "user-123"
