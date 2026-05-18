export default async function handler(req, res) {
  // POST 以外は拒否
  if (req.method !== 'POST') {
    res.status(405).json({ error: 'Method not allowed' });
    return;
  }

  // 環境変数から API キーを取得
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    res.status(500).json({ error: 'ANTHROPIC_API_KEY environment variable not set' });
    return;
  }

  try {
    // リクエストボディを取得（フロント側と揃える）
    const payload = req.body;

    const messages = [];

    // 履歴があれば追加
    if (payload.history) {
      for (const h of payload.history) {
        messages.push({ role: h.role, content: h.content });
      }
    }

    // 今回のユーザー発話を追加
    messages.push({ role: 'user', content: payload.message });

    // システムプロンプト（固定文言）
    const systemPrompt = 'あなたは親切なアシスタントです。ユーザーの質問に日本語で丁寧に答えてください。';

    const body = {
      model: "claude-sonnet-4-6",
      max_tokens: 800,
      system: systemPrompt,
      messages: messages,
    };

    const anthropicRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });

    if (!anthropicRes.ok) {
      const errText = await anthropicRes.text();
      console.error('Anthropic API error:', errText);
      res.status(502).json({ error: errText });
      return;
    }

    const data = await anthropicRes.json();

    const reply = data.content?.[0]?.text || 'すみません、うまく返答を生成できませんでした。';

    res.status(200).json({ reply });
  } catch (err) {
    console.error('Server error:', err);
    res.status(500).json({ error: String(err) });
  }
}