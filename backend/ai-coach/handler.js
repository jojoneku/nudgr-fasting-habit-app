/**
 * AI Coach Lambda Handler
 *
 * POST /coach
 * Headers: x-api-key: <API_GATEWAY_KEY>
 * Body: { context: AiCoachContext, messages: [{role, text}], stream?: boolean }
 *
 * Response: application/json  { response: string }
 *        or text/event-stream (SSE) when stream=true
 *
 * Environment variables:
 *   AWS_REGION           — Bedrock region (e.g. us-east-1)
 *   BEDROCK_MODEL_ID     — Model ARN (default: anthropic.claude-haiku-20240307-v1:0)
 *   MAX_TOKENS           — Max output tokens (default: 512)
 */

import {
  BedrockRuntimeClient,
  InvokeModelCommand,
  InvokeModelWithResponseStreamCommand,
} from '@aws-sdk/client-bedrock-runtime';

const client = new BedrockRuntimeClient({
  region: process.env.AWS_REGION ?? 'us-east-1',
});

const MODEL_ID =
  process.env.BEDROCK_MODEL_ID ??
  'anthropic.claude-haiku-20240307-v1:0';

const MAX_TOKENS = parseInt(process.env.MAX_TOKENS ?? '512', 10);

// ── Entry point ──────────────────────────────────────────────────────────────

export const handler = async (event) => {
  // API Gateway HTTP API passes body as string.
  const body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;

  const { context, messages, stream = false } = body ?? {};

  if (!messages || !Array.isArray(messages) || messages.length === 0) {
    return errorResponse(400, 'messages array is required');
  }

  const systemPrompt = buildSystemPrompt(context);
  const anthropicMessages = buildAnthropicMessages(messages);

  if (stream) {
    return streamResponse(systemPrompt, anthropicMessages);
  }

  return invokeResponse(systemPrompt, anthropicMessages);
};

// ── Non-streaming ─────────────────────────────────────────────────────────────

async function invokeResponse(systemPrompt, messages) {
  const payload = buildPayload(systemPrompt, messages);

  const command = new InvokeModelCommand({
    modelId: MODEL_ID,
    contentType: 'application/json',
    accept: 'application/json',
    body: JSON.stringify(payload),
  });

  try {
    const raw = await client.send(command);
    const decoded = JSON.parse(Buffer.from(raw.body).toString('utf-8'));
    const text = decoded?.content?.[0]?.text ?? '';

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ response: text }),
    };
  } catch (err) {
    console.error('Bedrock invoke error:', err);
    return errorResponse(502, 'Bedrock invocation failed');
  }
}

// ── Streaming (SSE) ───────────────────────────────────────────────────────────

async function streamResponse(systemPrompt, messages) {
  const payload = buildPayload(systemPrompt, messages);

  const command = new InvokeModelWithResponseStreamCommand({
    modelId: MODEL_ID,
    contentType: 'application/json',
    accept: 'application/json',
    body: JSON.stringify(payload),
  });

  try {
    const raw = await client.send(command);
    const chunks = [];

    for await (const event of raw.body) {
      if (event.chunk?.bytes) {
        const chunk = JSON.parse(Buffer.from(event.chunk.bytes).toString('utf-8'));
        if (chunk.type === 'content_block_delta' && chunk.delta?.type === 'text_delta') {
          chunks.push(chunk.delta.text);
        }
      }
    }

    // API Gateway HTTP API doesn't support true SSE — return full text.
    // For true streaming, deploy behind a WebSocket API or use chunked transfer.
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ response: chunks.join('') }),
    };
  } catch (err) {
    console.error('Bedrock stream error:', err);
    return errorResponse(502, 'Bedrock stream failed');
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function buildPayload(systemPrompt, messages) {
  return {
    anthropic_version: 'bedrock-2023-05-31',
    max_tokens: MAX_TOKENS,
    system: systemPrompt,
    messages,
  };
}

function buildSystemPrompt(context) {
  if (!context) {
    return 'You are The System AI Coach — a health and wellness advisor with an RPG twist. '
      + 'Be concise and motivating.';
  }

  const personas = {
    nutrition:
      'You are a nutrition coach inside a gamified fasting app called The System. '
      + 'Help the user log food accurately, hit macro goals, and optimise their eating window.',
    fasting:
      'You are a fasting coach inside The System. '
      + 'Guide the player through their fast, explain phases (ketosis, autophagy), keep them motivated.',
    stats:
      'You are the Shadow Monarch — the RPG advisor of The System. '
      + "Analyse the player's XP, level, HP, and streaks. Give strategic advice to level up faster.",
    treasury:
      'You are a finance analyst inside The System. '
      + "Review the player's budget, spending, and savings. Be concise and actionable.",
    general:
      'You are The System AI Coach — a health, fasting, and finance advisor with an RPG twist. '
      + 'Be direct and motivating.',
  };

  const persona = personas[context.entryPoint] ?? personas.general;

  const summary = buildContextSummary(context);
  return `${persona}\n\n${summary}\n\nRespond concisely. Do not repeat stats back. Be direct.`;
}

function buildContextSummary(ctx) {
  const lines = ['=== Player Status ==='];
  lines.push(`Level ${ctx.playerLevel ?? 1} | XP ${ctx.playerXp ?? 0} | HP ${ctx.playerHp ?? 100}`);
  lines.push(`Fasting streak: ${ctx.fastingStreak ?? 0} days`);

  if (ctx.isFasting && ctx.elapsedFastMinutes != null) {
    const h = Math.floor(ctx.elapsedFastMinutes / 60);
    const m = ctx.elapsedFastMinutes % 60;
    lines.push(`Currently fasting: ${h}h ${m}m / ${ctx.fastingGoalHours ?? 16}h goal`);
  } else {
    lines.push('Not currently fasting.');
  }

  if (ctx.todayCalories != null) {
    lines.push('=== Today\'s Nutrition ===');
    lines.push(`Calories: ${ctx.todayCalories} / ${ctx.calorieGoal ?? '?'} kcal`);
    lines.push(
      `Protein: ${ctx.todayProtein?.toFixed(1) ?? '?'}g | `
      + `Carbs: ${ctx.todayCarbs?.toFixed(1) ?? '?'}g | `
      + `Fat: ${ctx.todayFat?.toFixed(1) ?? '?'}g`
    );
  }

  if (ctx.monthBudget != null && ctx.monthSpent != null) {
    lines.push('=== Finance ===');
    lines.push(`Budget: ₱${ctx.monthBudget.toFixed(0)} | Spent: ₱${ctx.monthSpent.toFixed(0)}`);
  }

  return lines.join('\n');
}

function buildAnthropicMessages(messages) {
  return messages
    .filter((m) => m.role === 'user' || m.role === 'assistant')
    .map((m) => ({ role: m.role, content: m.text }));
}

function errorResponse(statusCode, message) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ error: message }),
  };
}
