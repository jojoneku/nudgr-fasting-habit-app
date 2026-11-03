import '../models/finance/transaction_record.dart';

/// One known notification shape for one app.
///
/// Templates are data: adding a bank is one entry here, never parser code.
/// A template that matches sets the direction outright and lifts the named
/// groups it declares; anything it leaves out falls through to the generic
/// pass in `capture_parser.dart`. Named groups the parser understands:
/// `amount`, `counterparty`, `last4` (the *user's own* card or account suffix
/// — never the other party's; leave a peer suffix unnamed).
class CaptureTemplate {
  final RegExp pattern;
  final TransactionType type;

  CaptureTemplate(String source, this.type)
      : pattern = RegExp(source, caseSensitive: false, dotAll: true);
}

/// Currency + number, as PH apps print it: `PHP 1,250.00`, `Php 285`,
/// `₱1,250.50`, `P 1250`, `PhP 99.00`. Shared by every template.
const String kAmountGroup =
    r'(?:PHP|PhP|Php|php|₱|P)\s?(?<amount>\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)';

/// Same, but the currency mark is optional. Only safe straight after a money
/// verb (`received 500.00 in your wallet` — Maya and some GCash InstaPay
/// pushes print no `PHP`), where a bare number is still an amount.
const String kBareAmountGroup =
    r'(?:(?:PHP|PhP|Php|php|₱|P)\s?)?(?<amount>\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)';

/// A counterparty name up to the first delimiter PH apps use after it.
/// A dot ends the name unless it follows a lone initial (`A. Santos`,
/// `JUAN D. 0917…`); the parser then trims any trailing phone number.
const String kCounterpartyGroup =
    r'(?<counterparty>.+?)(?=\s+(?:(?:via|on|ref|with|using|at|for|of|was|has|is|from|to)\b|w/)|\s*(?:(?<!\s[A-Za-z])[.]|[,;:(]|$))';

/// Masked account / card suffix: `ending in 1234`, `ending 1234`, `****1234`,
/// `xxxx1234`, `(1234)` after the word account/card.
const String kLast4Group =
    r'(?:ending\s+(?:in|with)?\s*\**\s*(?<last4>\d{4})|[*xX•.]{2,}\s?(?<last4b>\d{4}))';

/// A bank name in a BPI email table, up to the next table label.
const String _bankNameGroup =
    r'(?<counterparty>.+?)(?=\s+(?:transfer|reference|transaction)\b|\s*(?:[.,;:]|$))';

/// Known shapes per package.
///
/// Provenance, so a shape can be re-checked when an app changes its wording:
///  - `[real]`    a redacted real push, seen in a public parser fixture:
///                danrave1234/paytsek, frenzeldarzadon-code/wavewallet,
///                adolf94/ArFinanceApp, kiano8/InstantCrew (all GitHub);
///  - `[sms]`     a real SMS alert from the same bank; the app's push is
///                assumed to use the same wording until a sample says otherwise;
///  - `[guess]`   wording from a third-party parser with no fixture behind it.
/// Keep `test/utils/capture_parser_test.dart` in step with any edit here.
final Map<String, List<CaptureTemplate>> kCaptureTemplates = {
  // ── GCash ────────────────────────────────────────────────────────────────
  'com.globe.gcash.android': [
    // [real] "You have sent PHP 500.00 to JUAN D. 09171234567. Ref. No. …"
    CaptureTemplate(
      r'you have (?:sent|paid)\s+' +
          kAmountGroup +
          r'\s+(?:of gcash\s+)?to\s+' +
          kCounterpartyGroup,
      TransactionType.outflow,
    ),
    // [guess] "Your payment of PHP 1,250.00 to JOLLIBEE via QR …"
    CaptureTemplate(
      r'(?:your )?payment of\s+' +
          kAmountGroup +
          r'\s+to\s+' +
          kCounterpartyGroup,
      TransactionType.outflow,
    ),
    // [real] "Cash out of PHP 200.00 successful."
    CaptureTemplate(
      r'cash[- ]?out of\s+' + kAmountGroup,
      TransactionType.outflow,
    ),
    // [real] "You have received PHP 1,096.10 of GCash from MI*A P. 0915••••847."
    // [real] "You have received PHP 5,000.00 via InstaPay from BDO on Sep 8 …"
    // [real] "You have received 1000.00 of GCash from BDO with account ending in 1234. …"
    CaptureTemplate(
      r'you have received\s+' +
          kBareAmountGroup +
          r'\s+(?:of gcash\s+)?(?:via\s+\w+\s+)?from\s+' +
          kCounterpartyGroup,
      TransactionType.inflow,
    ),
    // [real] "PHP 150.00 has been credited to your GCash account via InstaPay from SEABANK. …"
    CaptureTemplate(
      kAmountGroup +
          r'\s+has been credited to your gcash account(?:\s+via\s+\w+)?(?:\s+from\s+' +
          kCounterpartyGroup +
          r')?',
      TransactionType.inflow,
    ),
    // [real] "Fund transfer received: your GCash was credited with PHP 1,250.00 via PESONet. …"
    CaptureTemplate(
      r'your gcash was credited with\s+' + kAmountGroup,
      TransactionType.inflow,
    ),
    // [guess] "Cash-in of PHP 1,000.00 via BPI Savings was successful."
    CaptureTemplate(
      r'cash[- ]?in of\s+' +
          kAmountGroup +
          r'\s+(?:via|from)\s+' +
          kCounterpartyGroup,
      TransactionType.inflow,
    ),
  ],
  // ── Maya ─────────────────────────────────────────────────────────────────
  'com.paymaya': [
    // [guess] "You paid PHP 350.00 to Grab Philippines using your Maya card ending in 1234 …"
    CaptureTemplate(
      r'you (?:paid|sent)\s+' + kAmountGroup + r'\s+to\s+' + kCounterpartyGroup,
      TransactionType.outflow,
    ),
    // [real] title "Money received", body "You received 500.00 in your wallet via InstaPay"
    CaptureTemplate(
      r'you received\s+' + kBareAmountGroup + r'\s+in your wallet',
      TransactionType.inflow,
    ),
    // [guess] "You received PHP 500.00 from JUAN D."
    CaptureTemplate(
      r'you received\s+' +
          kBareAmountGroup +
          r'\s+from\s+' +
          kCounterpartyGroup,
      TransactionType.inflow,
    ),
    // [guess] "You cashed in PHP 1,000.00 via BPI."
    CaptureTemplate(
      r'you cashed in\s+' +
          kAmountGroup +
          r'(?:\s+(?:via|from)\s+' +
          kCounterpartyGroup +
          r')?',
      TransactionType.inflow,
    ),
  ],
  // ── GoTyme ───────────────────────────────────────────────────────────────
  'ph.com.gotyme': [
    // [real] title "Transfer received", body
    // "You received P1,250.00 from A. Santos. Your available balance is P9,000.00."
    CaptureTemplate(
      r'you received\s+' + kAmountGroup + r'\s+from\s+' + kCounterpartyGroup,
      TransactionType.inflow,
    ),
    // [real] title "Transfer successful", body
    // "You sent P4000.00 to JUAN D. Bank Of The Philippine Islands (BPI) ••••••1637."
    CaptureTemplate(
      r'you sent\s+' +
          kAmountGroup +
          r'\s+to\s+(?<counterparty>.+?)(?=\s+[•*]{2,}|\s*(?:(?<!\s[A-Za-z])[.]|,)|$)',
      TransactionType.outflow,
    ),
    // [real] title "GoalSave: Funds transferred", body
    // "You've transferred P3,500.00 from GoalSave Tuition Fund to your Deposit account...6634. 02 Nov 20:42."
    // Money in to the deposit account from a GoalSave pocket; the pocket
    // becomes a transfer source when it is one of the user's accounts.
    CaptureTemplate(
      r"you(?:\u2019|')?ve transferred\s+" +
          kAmountGroup +
          r'\s+from\s+(?<counterparty>goalsave\b.*?)\s+to your\b',
      TransactionType.inflow,
    ),
    // [guess] the reverse: "You've transferred P500.00 from your Deposit account to GoalSave X."
    CaptureTemplate(
      r"you(?:\u2019|')?ve transferred\s+" +
          kAmountGroup +
          r'\s+from your\b.*?\s+to\s+(?<counterparty>goalsave\b.*?)(?=\s*[.,]|$)',
      TransactionType.outflow,
    ),
  ],
  // ── MariBank (the SeaBank app, rebranded; same package) ──────────────────
  'ph.seabank.seabank': [
    // [real] title "Successful Incoming Transfer", body
    // "You've received PHP 780.50 from bank with account ending 1234"
    CaptureTemplate(
      r"you(?:’|')?ve received\s+" +
          kAmountGroup +
          r'\s+from\s+' +
          kCounterpartyGroup,
      TransactionType.inflow,
    ),
    // [real] title "Transfer Successful", body
    // "You've successfully sent PHP 500.00 to account ending 9012"
    CaptureTemplate(
      r"you(?:’|')?ve successfully sent\s+" +
          kAmountGroup +
          r'\s+to\s+' +
          kCounterpartyGroup,
      TransactionType.outflow,
    ),
    // [real] "Your InstaPay transfer of PHP 150.00 to 09541230072 was successful. …"
    CaptureTemplate(
      r'(?:instapay|pesonet)\s+transfer of\s+' +
          kAmountGroup +
          r'\s+to\s+' +
          kCounterpartyGroup,
      TransactionType.outflow,
    ),
    // [real] "PHP 150.00 has been debited from your account via InstaPay. …"
    CaptureTemplate(
      kAmountGroup + r'\s+has been debited from your account',
      TransactionType.outflow,
    ),
  ],
  // ── BPI ──────────────────────────────────────────────────────────────────
  'com.bpi.ng.app': [
    // [real] "Your account XXXX1234 has been credited Php 1,234.00."
    CaptureTemplate(
      r'your account\s+' +
          kLast4Group +
          r'\s+has been credited\s+' +
          kAmountGroup,
      TransactionType.inflow,
    ),
    // [guess] "A purchase of PHP 1,500.00 was made on your BPI Credit Card ending in 1234 at SHOPEE …"
    CaptureTemplate(
      r'purchase of\s+' +
          kAmountGroup +
          r'\s+was made on your .*?' +
          kLast4Group +
          r'\s+at\s+' +
          kCounterpartyGroup,
      TransactionType.outflow,
    ),
    // [guess] "PHP 5,000.00 was debited from your account ending in 5678 …"
    CaptureTemplate(
      kAmountGroup +
          r'\s+was debited from your .*?' +
          kLast4Group +
          r'(?:\s+(?:to|for)\s+' +
          kCounterpartyGroup +
          r')?',
      TransactionType.outflow,
    ),
    // [guess] "You have received PHP 10,000.00 in your BPI account ending in 5678 from ACME CORP."
    CaptureTemplate(
      r'you have received\s+' +
          kAmountGroup +
          r'\s+in your .*?' +
          kLast4Group +
          r'(?:\s+from\s+' +
          kCounterpartyGroup +
          r')?',
      TransactionType.inflow,
    ),
  ],
  // ── VYBE by BPI ──────────────────────────────────────────────────────────
  'com.indivara.bpi': [
    // [real] title "Bank Transfer Successful", body
    // "You have transferred Php 1,500.00 to BDO account ending in XXXX5678. Your new balance …"
    CaptureTemplate(
      r'you have transferred\s+' +
          kAmountGroup +
          r'\s+to\s+' +
          kCounterpartyGroup,
      TransactionType.outflow,
    ),
    // [real] title "Pay Merchant", body
    // "Hi JUAN, your payment to JOLLIBEE of PHP 250.00 has been successfully posted …"
    CaptureTemplate(
      r'your payment to\s+' + kCounterpartyGroup + r'\s+of\s+' + kAmountGroup,
      TransactionType.outflow,
    ),
    // [real] title "Top Up", body
    // "You have received Php 1,000.00 from BPI on 10/12/2026 09:41 AM. Your new wallet balance …"
    CaptureTemplate(
      r'you have received\s+' +
          kAmountGroup +
          r'\s+from\s+' +
          kCounterpartyGroup,
      TransactionType.inflow,
    ),
  ],
  // ── Gmail: BPI emails ────────────────────────────────────────────────────
  // The notification shows the head of the email, so the amount may sit
  // below the fold; a direction-only template still sets the row up and the
  // user types the amount. A template with no `amount` group sets direction
  // and counterparty only.
  kGmailPackage: [
    // [real] the whole BPI InstaPay body (a share-sheet import or a long
    // snippet): "… Transfer From XXXXXXXX6634 Transfer To XXXXXX1637 Bank Name
    // GoTyme Bank Transfer Amount PHP 4,000.00 Transfer Service INSTAPAY".
    // "Transfer To" is the user's own BPI suffix; "Transfer From" is the
    // peer's masked number, never a name.
    CaptureTemplate(
      r'incoming (?:interbank )?funds transfer.*?\btransfer to\s+[*xX•.]+(?<last4>\d{4}).*?\bbank name\s+(?<counterparty>.+?)\s+transfer amount\s+' +
          kBareAmountGroup +
          r'(?![\d,])',
      TransactionType.inflow,
    ),
    // [guess] an amount line somewhere after the subject
    CaptureTemplate(
      r'incoming (?:interbank )?funds transfer.*?\bamount\b[^\d₱]{0,16}' +
          kBareAmountGroup +
          r'(?![\d,])',
      TransactionType.inflow,
    ),
    // [real] the head cut off before the amount: direction, and the bank when
    // the snippet reaches it.
    CaptureTemplate(
      r'incoming (?:interbank )?funds transfer.*?\bbank name\s+' +
          _bankNameGroup,
      TransactionType.inflow,
    ),
    CaptureTemplate(
      r'incoming (?:interbank )?funds transfer.*?\btransfer from\s+(?![*xX•.\d])' +
          kCounterpartyGroup,
      TransactionType.inflow,
    ),
    CaptureTemplate(
      r'incoming (?:interbank )?funds transfer',
      TransactionType.inflow,
    ),
    // [guess] the outgoing twin of the same email, mirrored: "Transfer From"
    // is the user's own suffix there.
    CaptureTemplate(
      r'outgoing (?:interbank )?funds transfer.*?\btransfer from\s+[*xX•.]+(?<last4>\d{4}).*?\bbank name\s+(?<counterparty>.+?)\s+transfer amount\s+' +
          kBareAmountGroup +
          r'(?![\d,])',
      TransactionType.outflow,
    ),
    CaptureTemplate(
      r'outgoing (?:interbank )?funds transfer.*?\bamount\b[^\d₱]{0,16}' +
          kBareAmountGroup +
          r'(?![\d,])',
      TransactionType.outflow,
    ),
    CaptureTemplate(
      r'outgoing (?:interbank )?funds transfer.*?\bbank name\s+' +
          _bankNameGroup,
      TransactionType.outflow,
    ),
    CaptureTemplate(
      r'outgoing (?:interbank )?funds transfer.*?\btransfer to\s+(?![*xX•.\d])' +
          kCounterpartyGroup,
      TransactionType.outflow,
    ),
    CaptureTemplate(
      r'outgoing (?:interbank )?funds transfer',
      TransactionType.outflow,
    ),
  ],
  // ── UnionBank ────────────────────────────────────────────────────────────
  'com.unionbankph.online': [
    // [sms] "You paid P1,234.00 to GRAB using your UnionBank Credit Card ending in 1234. …"
    CaptureTemplate(
      r'you paid\s+' +
          kAmountGroup +
          r'\s+to\s+' +
          kCounterpartyGroup +
          r'\s+using your .*?' +
          kLast4Group,
      TransactionType.outflow,
    ),
    // [sms] "Thank you for using your UnionBank Credit Card ending in 1234 for the amount of PHP 850.00 at STARBUCKS BGC."
    CaptureTemplate(
      r'thank you for using your .*?' +
          kLast4Group +
          r'.*?for the amount(?: of)?\s+' +
          kAmountGroup +
          r'(?:\s+at\s+' +
          kCounterpartyGroup +
          r')?',
      TransactionType.outflow,
    ),
  ],
};

/// Google Wallet tap-to-pay. One field is the payment line and the other is
/// the merchant, in either order; Wallet only posts purchases, so a row is
/// always money out, and a notification with no payment line (card added,
/// pass updated) is not a transaction at all. Shapes seen in public fixtures
/// (tiberiusteng/financisto1-holo, PhilippSchmid98/Stutz, kodalus/Castellan):
///   "$4.50 with Visa •••• 1234" / "STARBUCKS"
///   "SILPO" / "UAH198.00 with Visa PrivatBank ••6810"
///   "McDonald's" / "12,34 € · Mastercard •• 4321"
///   "LIDL 2306" / "CHF 12.50 mit Visa •••• 1234"
/// No PH sample yet; the PH line should read "₱150.00 with Visa •••• 1234".
const String kGoogleWalletPackage = 'com.google.android.apps.walletnfcrel';

/// The payment line: an amount with a currency mark on either side, then a
/// connector (`with`, `·`, a dash, or a localized "with"), then the card
/// label. A bare number (card digits) never matches.
const String kWalletPaymentLine = r'^(?:at\s+(?<merchant>.+?)\s+)?'
    r'(?:(?<cur1>PHP|Php|₱|P|\$|US\$|€|£|[A-Z]{3})\s?)?'
    r'(?<amount>\d{1,3}(?:[ ,.\u00A0\u202F]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)'
    r'(?:\s?(?<cur2>PHP|₱|\$|€|£|zł|Kč|грн|[A-Z]{3}))?'
    r'(?:\s+at\s+(?<merchant2>.+?))?'
    r'\s*(?:(?:[·\-–—]\s*)?(?:with|mit|con|avec|через|карткою|karta|使用)\s+|[·\-–—]\s*)(?<card>.+?)\s*$';

/// Masked digits inside a Wallet card label: `•••• 1234`, `••1234`, `**** 1234`.
const String kWalletCardLast4 = r'(?:[•∙●✱*]+|[xX]{2,})\s?(?<last4>\d{4})\b';

/// Gmail. The notification title is the sender ("BPI InstaPay") and the text
/// is the head of the email. Only senders in [kCaptureSenderFilterDefaults]
/// (or the user's own list) ever leave the native listener.
const String kGmailPackage = 'com.google.android.gm';

/// Title words a source must carry before the listener keeps it. Seeded when
/// the source is turned on; the user can change the list in Settings.
const Map<String, List<String>> kCaptureSenderFilterDefaults = {
  kGmailPackage: ['BPI'],
};

/// Preset sources offered in Settings before the user adds any. Package names
/// were checked against Google Play on 2026-11-02 (each id resolves to the
/// named listing). The user can add anything else through *Add from recent
/// notifications*.
const List<({String package, String label})> kCapturePresets = [
  (package: 'com.globe.gcash.android', label: 'GCash'),
  (package: 'com.paymaya', label: 'Maya'),
  (package: 'com.bpi.ng.app', label: 'BPI'),
  (package: 'com.indivara.bpi', label: 'VYBE by BPI'),
  (package: 'com.unionbankph.online', label: 'UnionBank'),
  (package: 'ph.com.bdo.retail', label: 'BDO Online'),
  (package: 'ph.com.bdo.pay', label: 'BDO Pay'),
  (package: 'ph.seabank.seabank', label: 'MariBank (SeaBank)'),
  (package: 'ph.com.gotyme', label: 'GoTyme'),
  (package: 'com.shopee.ph', label: 'Shopee / ShopeePay'),
  (package: kGoogleWalletPackage, label: 'Google Wallet'),
  (package: kGmailPackage, label: 'Gmail (bank emails)'),
];
