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
    name: 'find',
    kind: AiToolKind.read,
    description:
        'Look up the user\'s named records: bills, receivables (money owed '
        'to them), set-asides, budgets, budget groups, installment plans and '
        'accounts (with balances, credit limits and open statements). Use it '
        'for "a named record and its details" and to get the id an edit, '
        'delete or settlement needs. The query matches on all its words in '
        'any order ("meralco aug", "bpi card"); a month name in it sets the '
        'month. Every reply starts with a status: found (exactly one match '
        'comes back with ALL its fields — paid date, paid amount, account, '
        'note, linked ledger entry, series — so do not look it up again), '
        'ambiguous (several matched: ask which, or narrow the query), '
        'not_found (nearest names and matches in other months are listed: '
        'never invent an id), or error (fix the call as it says). Which tool '
        'answers what: a named record → find; rows in a period → '
        'findTransactions; a figure a screen shows → getView; a sum or '
        'group-by no screen shows → queryFinance. Do NOT call find before '
        'adding something new: the snapshot already lists this month\'s '
        'records, and an unasked lookup makes the user wait.',
    inputSchema: {
      'type': 'object',
      'required': ['entity'],
      'properties': {
        'entity': {
          'type': 'string',
          'enum': [
            'bill',
            'receivable',
            'setAside',
            'budget',
            'budgetGroup',
            'installment',
            'account',
          ],
        },
        'query': {
          'type': 'string',
          'description': 'Name or words of it, e.g. "internet", "meralco '
              'aug". Omit to list every record of the entity.',
        },
        'month': {
          'type': 'string',
          'description': 'YYYY-MM for bills, receivables, set-asides, '
              'budgets and budget groups. Defaults to the current month. '
              'Ignored for installments and accounts.',
        },
      },
    },
  ),
  // On demand only. The snapshot already carries recent spending and each
  // past month's biggest expenses; the full ledger is too big to send every
  // turn, so it is fetched when the user actually asks to go through it.
  AiTool(
    name: 'findTransactions',
    kind: AiToolKind.read,
    description: 'Go through the user\'s ledger transactions, past or present: '
        'spending, income and transfers, with date, account, category and '
        'note. Call this ONLY when the user asks to review, audit, look up, '
        'search or list their transactions, or asks about a specific '
        'purchase or payment the snapshot does not show ("what did I spend '
        'at Grab in March", "review my August transactions", "when did I '
        'last pay Meralco"). Do NOT call it for general advice or a summary '
        'question: the snapshot already lists recent spending and each past '
        'month\'s biggest expenses, and an unrequested lookup makes the user '
        'wait. The rows come straight from the ledger and are as quotable as '
        'the snapshot. This answers "rows in a period"; a named bill, '
        'account or plan is find, and a total grouped by category, account '
        'or month is queryFinance.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'Text to match against the description, note, '
              'category, account or who owes it, e.g. "grab". With a query '
              'and no dates, the whole history is searched.',
        },
        'month': {
          'type': 'string',
          'description': 'YYYY-MM. With no query and no dates, defaults to '
              'the current month.',
        },
        'from': {
          'type': 'string',
          'description': 'YYYY-MM-DD, inclusive. For a range that is not one '
              'calendar month. Overrides month.',
        },
        'to': {
          'type': 'string',
          'description': 'YYYY-MM-DD, inclusive.',
        },
        'type': {
          'type': 'string',
          'enum': ['outflow', 'inflow', 'transfer'],
          'description': 'Only this direction. Omit for all.',
        },
        'category': {
          'type': 'string',
          'description': 'Category NAME or part of it.',
        },
        'account': {
          'type': 'string',
          'description': 'Account NAME or part of it.',
        },
        'limit': {
          'type': 'integer',
          'description': 'Most rows to return, newest first. Default 50, '
              'max 150. Totals always cover every match.',
        },
      },
    },
  ),
  // Computed on the phone with the screens' own rules (Plan 065 phase 3), so
  // the model quotes a figure instead of adding up rows.
  AiTool(
    name: 'queryFinance',
    kind: AiToolKind.read,
    description: 'Answer a sum or group-by that no screen shows, computed '
        'from the ledger with the app\'s own rules: "average monthly '
        'spending since I started", "top 5 categories this year", "how much '
        'did I spend at Grab per month", "how much did I set aside in Q3". '
        'Quote its figures as they are: never add, subtract or average them '
        'yourself. A figure a screen shows (budget left, forecast, pace) '
        'comes from getView, a named record and its details from find, and '
        'the rows of a period from findTransactions. The result states the '
        'range, the months covered and what the metric counts.',
    inputSchema: {
      'type': 'object',
      'required': ['metric'],
      'properties': {
        'metric': {
          'type': 'string',
          'enum': ['spend', 'income', 'net', 'count', 'setAside'],
          'description': 'spend: real spending (no transfers, reimbursables '
              'or installment purchase records). income: real income. net: '
              'income minus spend. count: number of entries. setAside: money '
              'moved into savings pockets, less money moved out.',
        },
        'groupBy': {
          'type': 'string',
          'enum': ['none', 'category', 'account', 'month', 'description'],
          'description': 'One line per group. Default none (the total only). '
              'month lists every month in the range, including empty ones.',
        },
        'category': {
          'type': 'string',
          'description': 'Category NAME or part of it.',
        },
        'account': {
          'type': 'string',
          'description': 'Account NAME or part of it.',
        },
        'query': {
          'type': 'string',
          'description': 'Words to match, in any order, against the '
              'description, note, category, account or who owes it, e.g. '
              '"grab".',
        },
        'type': {
          'type': 'string',
          'enum': ['outflow', 'inflow', 'transfer'],
          'description': 'Only this direction. Omit for all.',
        },
        'from': {
          'type': 'string',
          'description': 'YYYY-MM-DD, inclusive. Overrides month.',
        },
        'to': {
          'type': 'string',
          'description': 'YYYY-MM-DD, inclusive. Defaults to today.',
        },
        'month': {
          'type': 'string',
          'description': 'YYYY-MM. With no month and no dates, the whole '
              'history is used, from the first ledger entry to today.',
        },
        'top': {
          'type': 'integer',
          'description': 'Most groups to list, biggest first. Default 10. '
              'The total always covers every group.',
        },
        'average': {
          'type': 'boolean',
          'description': 'Also give the average per month over the range, '
              'counting a month with no activity as 0. Use it for "average '
              'monthly …" questions.',
        },
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
        'Propose a new bill (money the user owes and will pay). Call this as '
        'soon as you have a name, an amount and a due day — do not ask '
        'permission in prose first, because calling it IS how the user is '
        'asked: they get a confirmation card and nothing is saved until they '
        'accept it.',
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
        'in). Call it as soon as you have a name and an amount — the '
        'confirmation card is how the user is asked, so asking in prose first '
        'only makes them wait.',
    inputSchema: {
      'type': 'object',
      'required': ['name', 'amount'],
      'properties': {
        'name': {
          'type': 'string',
          'description': 'Say who owes it in the name, e.g. "Mark - concert '
              'ticket". A receivable has no separate debtor field.',
        },
        'amount': {'type': 'number', 'description': 'In pesos.'},
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
    name: 'addSetAside',
    kind: AiToolKind.create,
    description:
        'Propose setting money aside for a purpose — savings, a goal such as '
        'braces, a sinking fund. This is a transfer between the user\'s own '
        'accounts, never spending. Call it as soon as you have a name, an '
        'amount and a type — the confirmation card is how the user is asked, '
        'so asking in prose first only makes them wait.',
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
  AiTool(
    name: 'logTransactions',
    kind: AiToolKind.create,
    description:
        'Propose one or more ledger transactions — actual money that moved '
        '(spending, income received, a transfer between the user\'s own '
        'accounts). Call it whenever the user asks you to log, record, add or '
        're-log spending, including when the amounts come from earlier in this '
        'conversation ("log the oil change again"): listing the entries in '
        'prose logs nothing. Every entry joins the review list with the other '
        'changes of this step, where the user fixes anything wrong and '
        'approves; the result comes back after they answer and says exactly '
        'what was logged. Use the exact account and category NAMES from the '
        'snapshot; leave a field out rather than inventing one and the row '
        'gives the user a picker for it. Amounts are separate entries when '
        'they were separate charges (₱295 oil and ₱50 labour are two). This '
        'does NOT change entries already in the ledger — use editTransaction '
        'or deleteTransaction for that.',
    inputSchema: {
      'type': 'object',
      'required': ['entries'],
      'properties': {
        'entries': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 10,
          'items': {
            'type': 'object',
            'required': ['amount', 'description'],
            'properties': {
              'amount': {
                'type': 'number',
                'description': 'In pesos, always positive. Direction comes '
                    'from "type", never from a minus sign.',
              },
              'description': {
                'type': 'string',
                'description': 'Short human label, e.g. "Motor oil change". '
                    'Not the raw sentence.',
              },
              'type': {
                'type': 'string',
                'enum': ['outflow', 'inflow', 'transfer'],
                'description': 'Default outflow. "transfer" moves money '
                    'between the user\'s own accounts and is never spending.',
              },
              'account': {
                'type': 'string',
                'description': 'Account NAME the money left or entered, '
                    'exactly as the snapshot spells it.',
              },
              'category': {
                'type': 'string',
                'description': 'Expense/income category NAME. Omit on a '
                    'transfer.',
              },
              'transferTo': {
                'type': 'string',
                'description': 'Destination account NAME. Transfers only.',
              },
              'date': {
                'type': 'string',
                'description': 'YYYY-MM-DD. Omit for today. Never a future '
                    'date.',
              },
              'note': {'type': 'string', 'description': 'Optional free text.'},
              'reimbursable': {
                'type': 'boolean',
                'description': 'True when the user spent it but is owed it '
                    'back (a work expense, money spotted for someone).',
              },
              'owedBy': {
                'type': 'string',
                'description': 'Who owes a reimbursable expense back.',
              },
              'expectedReimbursementDate': {
                'type': 'string',
                'description': 'YYYY-MM-DD the money is expected back.',
              },
            },
          },
        },
      },
    },
  ),
  AiTool(
    name: 'addInstallment',
    kind: AiToolKind.create,
    description:
        'Propose a new installment purchase on a credit card, credit line or '
        'BNPL account (e.g. SPayLater, a credit card 0% plan). This logs the '
        'purchase, holds that much of the credit limit, and splits it into '
        'monthly payments billed on the account\'s statement. Call as soon as '
        'you have a name, total amount, credit account and number of months — '
        'the confirmation card is how the user is asked. It only goes on a '
        'credit account; a purchase paid in one go is a logTransactions '
        'entry, not an installment. If the call fails, relay the reason and '
        'ask the user rather than guessing a value.',
    inputSchema: {
      'type': 'object',
      'required': ['name', 'amount', 'months'],
      'properties': {
        'name': {
          'type': 'string',
          'description':
              'Item or purchase description, e.g. "MacBook Pro", "Phone".',
        },
        'amount': {
          'type': 'number',
          'description': 'Total purchase amount in pesos, above zero.',
        },
        'months': {
          'type': 'integer',
          'description': 'Number of monthly payments, at least 2, e.g. 3, 6, '
              '12, 24. Ask the user if they did not say.',
        },
        'account': {
          'type': 'string',
          'description': 'Credit card, credit line or BNPL account NAME, '
              'exactly as the snapshot spells it. May be omitted only when '
              'the user has a single credit account.',
        },
        'interestRate': {
          'type': 'number',
          'description': 'MONTHLY add-on interest rate in percent: 0 for a 0% '
              'promo, 1.5 for 1.5% a month. Not an annual rate — divide a '
              'yearly rate by 12. Default 0.',
        },
        'category': {
          'type': 'string',
          'description':
              'Expense category NAME, e.g. "Electronics", "Shopping".',
        },
        'date': {
          'type': 'string',
          'description': 'YYYY-MM-DD purchase date. Defaults to today. Never '
              'a future date.',
        },
        'note': {
          'type': 'string',
          'description': 'Optional note or remarks.',
        },
      },
    },
  ),
  AiTool(
    name: 'checkAffordability',
    kind: AiToolKind.read,
    description:
        'Run the "Can I afford it?" check: calculates whether a proposed expense '
        'or purchase fits within the user\'s projected month-end spare cash after '
        'all planned bills, savings, and budget allocations. Call when the user '
        'asks "Can I afford X?", "Do I have enough for Y?", or similar questions.',
    inputSchema: {
      'type': 'object',
      'required': ['amount'],
      'properties': {
        'amount': {
          'type': 'number',
          'description': 'Proposed purchase or expense amount in pesos.',
        },
        'account': {
          'type': 'string',
          'description':
              'Optional account NAME to verify spendable cash on that specific account.',
        },
      },
    },
  ),
  AiTool(
    name: 'getView',
    kind: AiToolKind.read,
    description:
        'Read a screen\'s figures, labelled as the screen labels them and '
        'computed by the app exactly as the screen shows them. Use it for '
        '"a screen\'s figure" questions: "how much budget do I have left", '
        '"where will my cash be at the end of next month", "am I on pace", '
        '"what does the History tab say I average", "what is on my card '
        'statement", "how much do I hold for others". Quote the figures; '
        'never add or subtract them yourself. For a named record use find; '
        'for rows in a period use findTransactions; for a sum or group-by no '
        'screen shows use queryFinance.',
    inputSchema: {
      'type': 'object',
      'required': ['view'],
      'properties': {
        'view': {
          'type': 'string',
          'enum': [
            'dashboard',
            'budget',
            'bills',
            'ledger',
            'history',
            'accounts',
            'installments',
            'grocery',
          ],
          'description': 'dashboard: net worth, liquid cash, Budget Left, '
              'month-end outlook, next-month forecast. budget: spent vs '
              'budgeted, pace, every group and row. bills: pending/paid, '
              'coming up, statement line items, receivables, set-asides. '
              'ledger: month in/out/net, owed, daily average. history: '
              'averages, % saved, a month\'s closed summary and balances at '
              'close. accounts: every balance, held, yours, credit limit, '
              'statement/due days. installments: every plan. grocery: cart, '
              'price book, last trips.',
        },
        'month': {
          'type': 'string',
          'description': 'YYYY-MM. Defaults to the current month. The '
              'dashboard shows the current month only; accounts and grocery '
              'have no month.',
        },
      },
    },
  ),

  // ── Updates & Settlements ────────────────────────────────────────────────
  AiTool(
    name: 'payCredit',
    kind: AiToolKind.create,
    description:
        'Propose a payment to a credit card or line of credit (a transfer from a '
        'liquid account to a liability account, which reduces the debt owed). '
        'Call as soon as you have the credit card name and the amount — the user '
        'gets a confirmation card and nothing is saved until they accept it.',
    inputSchema: {
      'type': 'object',
      'required': ['creditAccount', 'amount'],
      'properties': {
        'creditAccount': {
          'type': 'string',
          'description': 'Credit card or BNPL account NAME being paid.',
        },
        'amount': {
          'type': 'number',
          'description': 'Payment amount in pesos, always positive.',
        },
        'fromAccount': {
          'type': 'string',
          'description':
              'Funding account NAME, e.g. "BPI Savings", "GCash". Optional.',
        },
        'date': {
          'type': 'string',
          'description': 'YYYY-MM-DD payment date. Defaults to today.',
        },
        'note': {
          'type': 'string',
          'description': 'Optional note or reference.',
        },
      },
    },
  ),
  AiTool(
    name: 'markBillPaid',
    kind: AiToolKind.update,
    description:
        'Mark an existing bill as paid for the month. Call ONLY after find '
        'returns the bill id. The user confirms on a card before the bill is '
        'marked paid.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact bill id from a preceding find result.',
        },
        'paidAmount': {
          'type': 'number',
          'description':
              'Amount paid in pesos. Omit to pay the bill\'s full amount.',
        },
        'paidDate': {
          'type': 'string',
          'description': 'YYYY-MM-DD date it was paid. Defaults to today.',
        },
        'account': {
          'type': 'string',
          'description': 'Account NAME it was paid from, if named by user.',
        },
        'alreadyLogged': {
          'type': 'boolean',
          'description': 'True when the user says they already logged this '
              'payment in the Ledger, so no second entry is recorded. The '
              'card lets them change it.',
        },
      },
    },
  ),
  AiTool(
    name: 'markBillsPaid',
    kind: AiToolKind.update,
    description:
        'Mark SEVERAL bills paid in one step, all from one account on one '
        'date, the way the Bills tab\'s multi-select does. Use for "paid '
        'Meralco, water and internet from GCash". For a single bill use '
        'markBillPaid. Call ONLY after find (entity bill) returns every id. '
        'The user approves on the review list before anything is saved.',
    inputSchema: {
      'type': 'object',
      'required': ['bills'],
      'properties': {
        'bills': {
          'type': 'array',
          'description': 'Two or more unpaid bills, each listed once.',
          'items': {
            'type': 'object',
            'required': ['id'],
            'properties': {
              'id': {
                'type': 'string',
                'description': 'The exact bill id from a preceding find '
                    'result.',
              },
              'paidAmount': {
                'type': 'number',
                'description': 'Amount paid in pesos. Omit to pay what is '
                    'left on the bill.',
              },
            },
          },
        },
        'account': {
          'type': 'string',
          'description': 'Account NAME all of them were paid from. Omit when '
              'the bills already share one.',
        },
        'paidDate': {
          'type': 'string',
          'description': 'YYYY-MM-DD date they were paid. Defaults to today.',
        },
        'alreadyLogged': {
          'type': 'boolean',
          'description': 'True when the user says they already logged these '
              'payments in the Ledger, so no second entries are recorded. The '
              'card lets them change it.',
        },
      },
    },
  ),
  AiTool(
    name: 'markReceivableReceived',
    kind: AiToolKind.update,
    description:
        'Mark money owed to the user as received. Call ONLY after find '
        'returns the receivable id. Settling a receivable creates the offsetting '
        'income entry in the ledger automatically. The user confirms on a card '
        'before anything is saved.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description':
              'The exact receivable id from a preceding find result.',
        },
        'receivedAmount': {
          'type': 'number',
          'description':
              'Amount received in pesos (if partial). Defaults to full receivable amount.',
        },
        'receivedDate': {
          'type': 'string',
          'description': 'YYYY-MM-DD date received. Defaults to today.',
        },
        'account': {
          'type': 'string',
          'description':
              'Account NAME the money landed in, e.g. "GCash", "BPI".',
        },
        'alreadyLogged': {
          'type': 'boolean',
          'description': 'True when the user says they already logged this '
              'income in the Ledger, so no second entry is recorded. The '
              'card lets them change it.',
        },
      },
    },
  ),
  AiTool(
    name: 'markBillUnpaid',
    kind: AiToolKind.update,
    description:
        'Undo a bill payment: the bill goes back to unpaid, and the ledger '
        'entry the payment made is deleted, so the money returns to the '
        'account it left. Use when the user says a bill was marked paid by '
        'mistake or is not paid yet. Call ONLY after find (entity bill) '
        'returns the id of a PAID bill. The user approves on the review list '
        'before anything changes.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact bill id from a preceding find result.',
        },
      },
    },
  ),
  AiTool(
    name: 'markReceivableNotReceived',
    kind: AiToolKind.update,
    description:
        'Undo a receipt: the receivable goes back to still owed, and the '
        'ledger income entry it made is deleted, so the money leaves the '
        'account it went into. Use when the user says money was marked '
        'received by mistake or has not arrived. Call ONLY after find '
        '(entity receivable) returns the id of a RECEIVED receivable. The '
        'user approves on the review list before anything changes.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description':
              'The exact receivable id from a preceding find result.',
        },
      },
    },
  ),
  AiTool(
    name: 'fundSetAside',
    kind: AiToolKind.update,
    description:
        'Propose funding an existing set-aside: move the money into it, the '
        'way "Set aside into" does on the Bills tab. It is a transfer between '
        'the user\'s own accounts, never spending. Call ONLY after find '
        '(entity setAside) returns its id. The user approves on the review '
        'list before anything moves.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact set-aside id from a preceding find call.',
        },
        'amount': {
          'type': 'number',
          'description': 'Pesos to set aside. Omit for the allocated amount.',
        },
        'fromAccount': {
          'type': 'string',
          'description': 'Account NAME the money leaves. Omit for the '
              'set-aside\'s own funding account.',
        },
        'intoAccount': {
          'type': 'string',
          'description': 'Savings or goal account NAME it moves into. Omit '
              'for the set-aside\'s own destination.',
        },
        'date': {
          'type': 'string',
          'description': 'YYYY-MM-DD. Defaults to today.',
        },
      },
    },
  ),
  AiTool(
    name: 'editBill',
    kind: AiToolKind.update,
    description:
        'Propose an edit to an existing bill (name, amount, due day, or category). '
        'Call ONLY after find (entity bill) returns the bill id. Do NOT supply an id unprompted. '
        'Nothing is saved until the user accepts the confirmation card.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact bill id from a preceding find call.',
        },
        'name': {'type': 'string', 'description': 'Updated bill name.'},
        'amount': {'type': 'number', 'description': 'Updated amount in pesos.'},
        'dueDay': {
          'type': 'integer',
          'description': 'Updated due day of month, 1-31.',
        },
        'category': {
          'type': 'string',
          'description': 'Updated category NAME.',
        },
      },
    },
  ),
  AiTool(
    name: 'editReceivable',
    kind: AiToolKind.update,
    description:
        'Propose an edit to an existing receivable (name, amount or expected day). '
        'Call ONLY after find (entity receivable) returns the receivable id. '
        'Nothing is saved until confirmed on the card.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact receivable id from a preceding find call.',
        },
        'name': {'type': 'string', 'description': 'Updated name.'},
        'amount': {'type': 'number', 'description': 'Updated amount in pesos.'},
        'expectedDay': {
          'type': 'integer',
          'description': 'Updated expected day of month, 1-31.',
        },
      },
    },
  ),
  AiTool(
    name: 'editSetAside',
    kind: AiToolKind.update,
    description:
        'Propose an edit to an existing set-aside (name, amount, type, or destination). '
        'Call ONLY after find (entity setAside) returns the set-aside id. '
        'Nothing is saved until confirmed.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact set-aside id from a preceding find call.',
        },
        'name': {'type': 'string', 'description': 'Updated name.'},
        'amount': {'type': 'number', 'description': 'Updated amount in pesos.'},
        'type': {
          'type': 'string',
          'enum': ['savings', 'goal', 'sinkingFund', 'gift', 'other'],
          'description': 'Updated set-aside purpose.',
        },
        'destinationAccount': {
          'type': 'string',
          'description': 'Updated destination account NAME.',
        },
      },
    },
  ),
  AiTool(
    name: 'editTransaction',
    kind: AiToolKind.update,
    description:
        'Propose editing an existing ledger transaction. Call ONLY after '
        'findTransactions returns the transaction id. The user confirms on a '
        'card before changes are applied. Do NOT use this to reverse flow '
        'direction (inflow vs outflow) — ask the user to delete and re-log instead.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description':
              'The exact transaction id from a preceding findTransactions call.',
        },
        'description': {
          'type': 'string',
          'description': 'Updated short description.',
        },
        'amount': {
          'type': 'number',
          'description': 'Updated amount in pesos, always positive.',
        },
        'date': {
          'type': 'string',
          'description': 'Updated date in YYYY-MM-DD.',
        },
        'category': {
          'type': 'string',
          'description': 'Updated category NAME.',
        },
        'account': {
          'type': 'string',
          'description': 'Updated account NAME.',
        },
        'note': {
          'type': 'string',
          'description': 'Updated note or remarks.',
        },
      },
    },
  ),

  // ── Deletions ────────────────────────────────────────────────────────────
  AiTool(
    name: 'deleteBill',
    kind: AiToolKind.destroy,
    description:
        'Propose deleting an existing bill. Call ONLY after find returns '
        'the bill id. The user confirms on a card before the bill is deleted.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact bill id from a preceding find call.',
        },
      },
    },
  ),
  AiTool(
    name: 'deleteReceivable',
    kind: AiToolKind.destroy,
    description:
        'Propose deleting an existing receivable. Call ONLY after find '
        'returns the receivable id. The user confirms on a card before deletion.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact receivable id from a preceding find call.',
        },
      },
    },
  ),
  AiTool(
    name: 'deleteSetAside',
    kind: AiToolKind.destroy,
    description: 'Propose deleting an existing set-aside. Call ONLY after find '
        'returns the set-aside id. The user confirms on a card before deletion.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description': 'The exact set-aside id from a preceding find call.',
        },
      },
    },
  ),
  AiTool(
    name: 'deleteTransaction',
    kind: AiToolKind.destroy,
    description:
        'Propose permanently deleting a ledger transaction. Call ONLY after '
        'findTransactions returns the transaction id. The user confirms on an '
        'explicit warning card before the transaction is deleted.',
    inputSchema: {
      'type': 'object',
      'required': ['id'],
      'properties': {
        'id': {
          'type': 'string',
          'description':
              'The exact transaction id from a preceding findTransactions call.',
        },
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
