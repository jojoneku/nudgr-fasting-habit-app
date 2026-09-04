import '../models/ai_tool.dart';

/// The tools Nudgy may call, declared as data.
///
/// Two invariants hold across every entry here and are asserted in tests:
///
/// 1. **No schema exposes `applyToFuture`.** Every bill and receivable mutator
///    takes it, and on a delete it erases a recurring series across all future
///    months. Nothing in a sentence like "cancel my internet bill" reliably
///    separates that from "cancel it this month", so recurrence scope is a
///    control on the confirm card with a narrow default, never a value the
///    model sets.
/// 2. **No schema takes an entity id except one from a `find*` result.** The
///    model cannot see ids, so an id it produced unprompted is invented. This
///    is what keeps "delete my internet bill" from resolving to another row.
///
/// Names, not ids, for categories and accounts. The client binds them against
/// the live lists the same way the expense extractor does, so a typo or a
/// partial name resolves instead of failing.
///
/// This catalogue is sent to the backend with each request rather than being
/// defined there: the client is what executes these, so it is the only party
/// that knows which its build supports (design D10).
const List<AiTool> kFinanceTools = [
  // ── Reads ───────────────────────────────────────────────────────────────
  AiTool(
    name: 'findBills',
    kind: AiToolKind.read,
    description:
        'Find bills matching a phrase, with their ids. Call this before '
        'editing or deleting a bill, and to check whether one already exists '
        'before adding it.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Name or partial name, e.g. "internet". Omit to list '
              'all bills for the month.',
        },
        'month': {
          'type': 'string',
          'description': 'YYYY-MM. Defaults to the month being viewed.',
        },
      },
    },
  ),
  AiTool(
    name: 'findReceivables',
    kind: AiToolKind.read,
    description:
        'Find money owed TO the user, with ids. Call before editing or '
        'deleting a receivable.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Name, or who owes it.'},
        'month': {'type': 'string', 'description': 'YYYY-MM.'},
      },
    },
  ),
  AiTool(
    name: 'findSetAsides',
    kind: AiToolKind.read,
    description:
        'Find set-asides (money earmarked for a purpose: savings, a goal, a '
        'sinking fund), with ids and their funded vs allocated amounts.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Name, e.g. "braces".'},
        'month': {'type': 'string', 'description': 'YYYY-MM.'},
      },
    },
  ),
  AiTool(
    name: 'findBudgets',
    kind: AiToolKind.read,
    description:
        'Find category budgets with their limits and spend so far. Call '
        'before changing a budget.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Category or group name.'},
        'month': {'type': 'string', 'description': 'YYYY-MM.'},
      },
    },
  ),

  // ── Creates ─────────────────────────────────────────────────────────────
  // Each returns a proposal the user confirms. None takes an id: a create has
  // no existing row to name.
  AiTool(
    name: 'addBill',
    kind: AiToolKind.create,
    description:
        'Propose a new bill (money the user owes and will pay). The user '
        'confirms before anything is saved. Search first if it might already '
        'exist.',
    inputSchema: {
      'type': 'object',
      'required': ['name', 'amount', 'dueDay'],
      'properties': {
        'name': {'type': 'string', 'description': 'e.g. "Internet".'},
        'amount': {'type': 'number', 'description': 'In pesos.'},
        'dueDay': {
          'type': 'integer',
          'description': 'Day of the month it is due, 1-31.',
        },
        'isRecurring': {
          'type': 'boolean',
          'description': 'True if it repeats monthly. Default false.',
        },
        'category': {
          'type': 'string',
          'description': 'Expense category NAME; the client resolves it.',
        },
        'account': {
          'type': 'string',
          'description': 'Preferred paying account NAME, if the user said one.',
        },
        'month': {
          'type': 'string',
          'description': 'YYYY-MM. Defaults to the month being viewed.',
        },
      },
    },
  ),
  AiTool(
    name: 'addReceivable',
    kind: AiToolKind.create,
    description:
        'Propose a new receivable (money owed TO the user, expected to come '
        'in). The user confirms before anything is saved.',
    inputSchema: {
      'type': 'object',
      'required': ['name', 'amount'],
      'properties': {
        'name': {'type': 'string'},
        'amount': {'type': 'number', 'description': 'In pesos.'},
        'owedBy': {'type': 'string', 'description': 'Who owes it.'},
        'expectedDay': {
          'type': 'integer',
          'description': 'Day of the month it is expected, 1-31.',
        },
        'isRecurring': {'type': 'boolean'},
        'month': {'type': 'string', 'description': 'YYYY-MM.'},
      },
    },
  ),
  AiTool(
    name: 'addTransaction',
    kind: AiToolKind.create,
    description:
        'Propose logging one transaction in the ledger: an expense, income, '
        'or a transfer between two of the user\'s own accounts. The user '
        'confirms before anything is saved.\n'
        'This is NOT the ordinary way an expense gets logged. A plain '
        'reporting sentence ("spent 250 on lunch gcash", "coffee 120") never '
        'reaches you at all — the quick-logger takes it first, and it is '
        'better at that job than this tool: several entries from one message, '
        'context stated once across them, learned categories, receipt photos. '
        'Reach for this only when the entry became clear through the '
        'conversation rather than from a sentence the user typed to be '
        'logged: settling a bill you just looked up, an amount you worked out '
        'together, or a log the user asked for without stating the fields. If '
        'the user simply wants to record something they already know, tell '
        'them to type it and let the logger have it.',
    inputSchema: {
      'type': 'object',
      'required': ['amount', 'description'],
      'properties': {
        'amount': {
          'type': 'number',
          'description': 'In pesos, always positive. The direction comes from '
              '"type", never from a minus sign.',
        },
        'description': {
          'type': 'string',
          'description': 'What it was, e.g. "Lunch at Alturas".',
        },
        'type': {
          'type': 'string',
          'enum': ['expense', 'income', 'transfer'],
          'description': 'Defaults to expense. A transfer moves money between '
              'the user\'s own accounts and is neither spending nor income.',
        },
        'account': {
          'type': 'string',
          'description': 'Account NAME the money leaves (expense, transfer) '
              'or arrives in (income). Omit only when the user has exactly '
              'one account; otherwise ask rather than picking for them.',
        },
        'toAccount': {
          'type': 'string',
          'description': 'Transfer only: destination account NAME.',
        },
        'category': {
          'type': 'string',
          'description': 'Category NAME, matching the transaction direction. '
              'Not used on a transfer, which carries the reserved transfer '
              'category instead.',
        },
        'date': {
          'type': 'string',
          'description': 'YYYY-MM-DD. Defaults to today. Resolve "yesterday" '
              'and similar against the TODAY line in the snapshot.',
        },
        'note': {'type': 'string', 'description': 'Optional longer note.'},
        'reimbursable': {
          'type': 'boolean',
          'description': 'Expense only: money the user expects back (a work '
              'expense, or something they spotted for someone). Spawns a '
              'linked receivable so the payback is tracked.',
        },
        'owedBy': {
          'type': 'string',
          'description': 'Who owes the money back. Only with reimbursable.',
        },
      },
    },
  ),
  AiTool(
    name: 'addSetAside',
    kind: AiToolKind.create,
    description:
        'Propose setting money aside for a purpose — savings, a goal such as '
        'braces, a sinking fund. This is a transfer between the user\'s own '
        'accounts, never spending. The user confirms before anything is saved.',
    inputSchema: {
      'type': 'object',
      'required': ['name', 'amount', 'type'],
      'properties': {
        'name': {'type': 'string', 'description': 'e.g. "Braces".'},
        'amount': {'type': 'number', 'description': 'In pesos.'},
        'type': {
          'type': 'string',
          'enum': ['savings', 'goal', 'sinkingFund', 'gift', 'other'],
        },
        'destinationAccount': {
          'type': 'string',
          'description': 'Savings account or goal NAME the money moves into.',
        },
        'isRecurring': {
          'type': 'boolean',
          'description': 'True if set aside every month. Default false.',
        },
        'month': {'type': 'string', 'description': 'YYYY-MM.'},
      },
    },
  ),
];

/// The catalogue in the shape the backend forwards to Bedrock.
List<Map<String, Object?>> financeToolsRequestJson() =>
    [for (final t in kFinanceTools) t.toRequestJson()];

/// The catalogue in MCP `tools/list` shape. Nothing consumes this yet; it
/// exists so the mapping is executable and tested rather than aspirational
/// (design D11).
List<Map<String, Object?>> financeToolsMcpJson() =>
    [for (final t in kFinanceTools) t.toMcpJson()];

/// Look a tool up by the name the model called.
AiTool? financeToolNamed(String name) {
  for (final t in kFinanceTools) {
    if (t.name == name) return t;
  }
  return null;
}
