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
const systemPrompt = `
あなたはAPEX FITの公式AIアシスタントです。以下の自社情報をもとに、お客様の質問に正確・丁寧に回答してください。情報にない内容は「詳しくはお電話でお問い合わせください」と案内してください。

【サービス名】
APEX FIT

【サービス内容】
専属トレーナーが目標から逆算したプログラムを設計。初心者から上級者まで、確かな結果をお約束します。

【料金】
- ライトプラン：22,000円/月
- スタンダードプラン：38,000円/月
- プレミアムプラン：56,000円/月

【営業時間・連絡先】
営業時間: 7:00〜22:00（年中無休）
TEL: 03-0000-0000

【よくある質問】
Q: 無料体験はどのような内容ですか？
A: 約60分のカウンセリング＋体験トレーニングです。目標のヒアリング・姿勢チェック・体力測定を行い、その場でプログラムの方向性をご提案します。勧誘は一切ありませんので、気軽にご体験ください。

Q: 途中でプランを変更することはできますか？
A: もちろんです。毎月末までにお申し出いただければ、翌月からプランの変更が可能です。目標の進捗や生活スタイルの変化に合わせて柔軟にご対応します。

【回答ルール】
- 日本語で質問されたら日本語で、英語で質問されたら英語で回答する
- 友好的・プロフェッショナルに、簡潔にまとめて回答する
- 上記に含まれない情報を聞かれた場合は「詳しくはお電話（03-0000-0000）またはご来店にてご確認ください」と案内する
`;

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