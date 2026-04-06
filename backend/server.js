require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');

const app = express();
const port = process.env.PORT || 3000;
const groqApiKey = process.env.GROQ_API_KEY;

if (!groqApiKey) {
  console.error('ERROR: GROQ_API_KEY not set in .env file');
  process.exit(1);
}

// Middleware
app.use(express.json());
app.use(cors({
  origin: ['http://localhost:8080', 'http://localhost:3000'],
  credentials: true,
}));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Chat proxy endpoint
app.post('/api/chat', async (req, res) => {
  try {
    const { message, systemPrompt, model = 'llama-3.1-8b-instant' } = req.body;

    if (!message) {
      return res.status(400).json({ error: 'Message is required' });
    }

    const systemMsg = systemPrompt || `
You are a helpful health & safety assistant embedded in a Fall Detection app.
The app monitors elderly or at-risk patients using an Arduino Nano 33 BLE Sense
wearable sensor that streams heart rate, tilt angle, and acceleration data.

Your capabilities:
• Answer questions about fall prevention, post-fall care, and when to seek emergency help.
• Explain sensor readings (heart rate, tilt angle, acceleration magnitude).
• Give general wellness tips for elderly care.
• Help troubleshoot Bluetooth connectivity or device issues.

Important: You are NOT a doctor. Always recommend consulting a healthcare professional.
Keep answers concise and easy to understand. Be empathetic and reassuring.
    `.trim();

    // Call Groq API
    const groqResponse = await axios.post(
      'https://api.groq.com/openai/v1/chat/completions',
      {
        model: model,
        messages: [
          { role: 'system', content: systemMsg },
          { role: 'user', content: message },
        ],
        temperature: 0.6,
        max_tokens: 256,
      },
      {
        headers: {
          'Authorization': `Bearer ${groqApiKey}`,
          'Content-Type': 'application/json',
        },
        timeout: 20000,
      }
    );

    // Extract response text
    const choices = groqResponse.data.choices || [];
    if (choices.length === 0) {
      return res.status(500).json({ error: 'No response from Groq' });
    }

    const content = choices[0].message?.content || 'Sorry, I could not generate a response.';

    res.json({ 
      success: true, 
      reply: content,
      model: model,
    });

  } catch (error) {
    console.error('Error calling Groq API:', error.message);
    
    if (error.response?.status === 401) {
      return res.status(401).json({ error: 'Invalid Groq API key' });
    }

    res.status(500).json({ 
      error: error.message || 'Failed to process request',
      details: process.env.NODE_ENV === 'development' ? error.toString() : undefined,
    });
  }
});

app.listen(port, () => {
  console.log(`✓ Fall Detection Proxy running on http://localhost:${port}`);
  console.log(`✓ POST /api/chat for chat requests`);
  console.log(`✓ GET /health for health check`);
});
