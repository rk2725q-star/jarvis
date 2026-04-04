class AIIntegration {
  final String id;
  final String name;
  final String description;
  final String url;
  final String category;
  final List<int> gradientColors; // ARGB ints
  final String emoji;
  final List<String> features;
  final List<String> keywords; // for agentic matching
  final String searchUrlTemplate; // {query} placeholder
  /// JS automation script templates for agentic control
  final String agentJsHint;

  const AIIntegration({
    required this.id,
    required this.name,
    required this.description,
    required this.url,
    required this.category,
    required this.gradientColors,
    required this.emoji,
    required this.features,
    required this.keywords,
    required this.searchUrlTemplate,
    this.agentJsHint = '',
  });

  /// Build a ready-to-open URL for a given task query
  String buildTaskUrl(String query) {
    final encoded = Uri.encodeComponent(query);
    return searchUrlTemplate.replaceAll('{query}', encoded);
  }
}

const List<AIIntegration> kAIIntegrations = [
  // ── AI Platforms ─────────────────────────────────────────────────────────────
  AIIntegration(
    id: 'arena',
    name: 'Arena.ai',
    description: 'Compare multiple AI models side by side in real-time battles.',
    url: 'https://arena.ai',
    category: 'Multi-Model',
    gradientColors: [0xFF6C63FF, 0xFF3A86FF],
    emoji: '⚔️',
    features: ['Model Comparison', 'Live Battles', 'Rankings'],
    keywords: ['compare', 'battle', 'arena', 'vs', 'models', 'side by side', 'benchmark'],
    searchUrlTemplate: 'https://arena.ai',
    agentJsHint: 'Find the main text input (placeholder: "Ask anything..."), type the query, then click the submit/arrow button to run.',
  ),
  AIIntegration(
    id: 'designarena',
    name: 'Design Arena',
    // Fix: use the direct homepage, NOT the Firebase redirect URL
    description: 'Battle your design ideas against AI-generated alternatives.',
    url: 'https://www.designarena.ai',
    category: 'Design AI',
    gradientColors: [0xFFFF6B9D, 0xFFC44BFF],
    emoji: '🎨',
    features: ['Design Battle', 'AI Design', 'Creative Voting'],
    keywords: ['design', 'ui', 'ux', 'creative', 'visual', 'logo', 'figma', 'artwork', 'layout'],
    searchUrlTemplate: 'https://www.designarena.ai',
    agentJsHint: 'Find the design prompt input field and type the query. Click the Generate or Submit button.',
  ),
  AIIntegration(
    id: 'claude',
    name: 'Claude',
    description: "Anthropic's AI assistant — thoughtful, safe and capable.",
    url: 'https://claude.ai/new',
    category: 'AI Assistant',
    gradientColors: [0xFFD97706, 0xFFB45309],
    emoji: '🤖',
    features: ['Long Context', 'Code', 'Analysis'],
    keywords: ['claude', 'anthropic', 'write', 'analyze', 'document', 'essay', 'summarize'],
    searchUrlTemplate: 'https://claude.ai/new',
    agentJsHint: 'Find the main chat textarea, type the query, and press Enter or click Send.',
  ),
  AIIntegration(
    id: 'chatgpt',
    name: 'ChatGPT',
    description: "OpenAI's flagship conversational AI with GPT-4o.",
    url: 'https://chat.openai.com',
    category: 'AI Assistant',
    gradientColors: [0xFF10B981, 0xFF059669],
    emoji: '💬',
    features: ['GPT-4o', 'Images', 'Voice'],
    keywords: ['chatgpt', 'openai', 'code', 'program', 'debug', 'gpt', 'dalle', 'image generate'],
    searchUrlTemplate: 'https://chat.openai.com',
    agentJsHint: 'Find the chat textarea with id="prompt-textarea", type the query, then press Enter.',
  ),
  AIIntegration(
    id: 'gemini',
    name: 'Gemini',
    description: "Google's most capable AI, deeply integrated with Google apps.",
    url: 'https://gemini.google.com/app',
    category: 'AI Assistant',
    gradientColors: [0xFF4285F4, 0xFF34A853],
    emoji: '✨',
    features: ['Multimodal', 'Google Workspace', 'Extensions'],
    keywords: ['gemini', 'google ai', 'workspace', 'multimodal'],
    searchUrlTemplate: 'https://gemini.google.com/app',
    agentJsHint: 'Find the rich-text input area, type the query, press Enter.',
  ),
  AIIntegration(
    id: 'perplexity',
    name: 'Perplexity',
    description: 'AI-powered search engine with real-time web access.',
    url: 'https://www.perplexity.ai',
    category: 'Search AI',
    gradientColors: [0xFF06B6D4, 0xFF0891B2],
    emoji: '🔍',
    features: ['Real-time Search', 'Citations', 'Focus Modes'],
    keywords: ['search', 'find', 'look up', 'research', 'news', 'latest', 'current', 'fact'],
    searchUrlTemplate: 'https://www.perplexity.ai/search?q={query}',
    agentJsHint: 'Navigate to the search URL with the query pre-filled. It will auto-run.',
  ),
  AIIntegration(
    id: 'poe',
    name: 'Poe',
    description: 'Access Claude, GPT-4, Gemini and 100+ AI bots in one place.',
    url: 'https://poe.com',
    category: 'Multi-Model',
    gradientColors: [0xFF8B5CF6, 0xFF7C3AED],
    emoji: '🎭',
    features: ['100+ Bots', 'Custom Bots', 'Multi-model'],
    keywords: ['poe', 'multiple bots', 'quora', 'try different', 'switch ai'],
    searchUrlTemplate: 'https://poe.com',
    agentJsHint: 'Find the message input box, type the query, click send.',
  ),
  AIIntegration(
    id: 'groq',
    name: 'Groq',
    description: 'Blazingly fast AI inference — the fastest LLM API available.',
    url: 'https://groq.com',
    category: 'Developer',
    gradientColors: [0xFFF59E0B, 0xFFD97706],
    emoji: '⚡',
    features: ['Ultra-fast', 'Llama 3', 'Open Models'],
    keywords: ['fast', 'speed', 'groq', 'llama', 'quick', 'instant', 'low latency'],
    searchUrlTemplate: 'https://groq.com',
    agentJsHint: 'Find the main input, type the query, submit.',
  ),
  AIIntegration(
    id: 'mistral',
    name: 'Mistral AI',
    description: 'European frontier AI — powerful open and closed models.',
    url: 'https://chat.mistral.ai',
    category: 'AI Assistant',
    gradientColors: [0xFFEC4899, 0xFFBE185D],
    emoji: '🌊',
    features: ['Le Chat', 'Code', 'Multilingual'],
    keywords: ['mistral', 'french', 'european', 'multilingual', 'le chat', 'translate'],
    searchUrlTemplate: 'https://chat.mistral.ai',
    agentJsHint: 'Find chat textarea, type query, press Enter.',
  ),
  AIIntegration(
    id: 'cohere',
    name: 'Cohere',
    description: 'Enterprise AI platform for business applications.',
    url: 'https://coral.cohere.com',
    category: 'Enterprise',
    gradientColors: [0xFF6366F1, 0xFF4F46E5],
    emoji: '🏢',
    features: ['RAG', 'Search', 'Enterprise'],
    keywords: ['enterprise', 'business', 'rag', 'cohere', 'company', 'workflow', 'data'],
    searchUrlTemplate: 'https://coral.cohere.com',
    agentJsHint: 'Find the prompt area, type the query, submit.',
  ),
  AIIntegration(
    id: 'huggingface',
    name: 'HuggingFace',
    description: 'The AI community — thousands of open-source models & datasets.',
    url: 'https://huggingface.co/chat',
    category: 'Open Source',
    gradientColors: [0xFFF59E0B, 0xFFEF4444],
    emoji: '🤗',
    features: ['Open Models', 'Spaces', 'Datasets'],
    keywords: ['open source', 'huggingface', 'free', 'model', 'dataset', 'pipeline', 'transformers'],
    searchUrlTemplate: 'https://huggingface.co/chat',
    agentJsHint: 'Find the chat textarea, type the query, press Enter.',
  ),

  // ── Google Suite ──────────────────────────────────────────────────────────────
  AIIntegration(
    id: 'gmail',
    name: 'Gmail',
    description: "Google's powerful email with smart compose and filters.",
    url: 'https://mail.google.com',
    category: 'Google',
    gradientColors: [0xFFEA4335, 0xFFFBBC05],
    emoji: '📧',
    features: ['Smart Compose', 'Labels', 'Search'],
    keywords: ['gmail', 'email', 'mail', 'send email', 'compose', 'inbox', 'reply'],
    searchUrlTemplate: 'https://mail.google.com/mail/u/0/#search/{query}',
    agentJsHint: 'Click Compose button, fill To/Subject fields and body, then click Send.',
  ),
  AIIntegration(
    id: 'youtube',
    name: 'YouTube',
    description: 'Watch, search, and discover videos worldwide.',
    url: 'https://m.youtube.com',
    category: 'Google',
    gradientColors: [0xFFFF0000, 0xFFCC0000],
    emoji: '▶️',
    features: ['Videos', 'Shorts', 'Live'],
    keywords: ['youtube', 'video', 'watch', 'stream', 'shorts', 'subscribe', 'tutorial'],
    searchUrlTemplate: 'https://m.youtube.com/results?search_query={query}',
    agentJsHint: 'Navigate to the search URL with the query. Auto results will show.',
  ),
  AIIntegration(
    id: 'drive',
    name: 'Google Drive',
    description: 'Store, share and collaborate on files in the cloud.',
    url: 'https://drive.google.com',
    category: 'Google',
    gradientColors: [0xFF34A853, 0xFF4285F4],
    emoji: '💾',
    features: ['Cloud Storage', 'Sharing', 'Collaboration'],
    keywords: ['drive', 'storage', 'file', 'upload', 'share', 'cloud', 'folder', 'gdrive'],
    searchUrlTemplate: 'https://drive.google.com/drive/search?q={query}',
    agentJsHint: 'Use the search bar at top, type the query and press Enter.',
  ),
  AIIntegration(
    id: 'aria',
    name: 'Aria Browser',
    description: 'Surf the web with JARVIS-powered intelligent browsing.',
    url: 'https://www.google.com',
    category: 'Browser',
    gradientColors: [0xFF4285F4, 0xFF34A853],
    emoji: '🌐',
    features: ['Web Search', 'AI Assist', 'Smart Browse'],
    keywords: ['browse', 'internet', 'web', 'website', 'google', 'open url', 'navigate'],
    searchUrlTemplate: 'https://www.google.com/search?q={query}',
    agentJsHint: 'Type the search query in the Google search box and press Enter.',
  ),
  AIIntegration(
    id: 'googledocs',
    name: 'Google Docs',
    description: 'Create and collaborate on documents online.',
    url: 'https://docs.google.com',
    category: 'Google',
    gradientColors: [0xFF4285F4, 0xFF1565C0],
    emoji: '📄',
    features: ['Documents', 'Collaboration', 'Templates'],
    keywords: ['doc', 'document', 'write', 'google doc', 'report', 'essay', 'text file'],
    searchUrlTemplate: 'https://docs.google.com',
    agentJsHint: "Click 'New' or '+' to create a document. Type in the document body.",
  ),
  AIIntegration(
    id: 'notebooklm',
    name: 'NotebookLM',
    description: 'Google AI-powered notebook that learns from your documents.',
    url: 'https://notebooklm.google.com',
    category: 'Google',
    gradientColors: [0xFF0D47A1, 0xFF1565C0],
    emoji: '📓',
    features: ['AI Summaries', 'Q&A', 'Audio Overview'],
    keywords: ['notebook', 'notebooklm', 'stitch', 'knowledge base', 'upload docs', 'summarize docs'],
    searchUrlTemplate: 'https://notebooklm.google.com',
    agentJsHint: 'Create a new notebook or open an existing one. Use the chat panel to ask questions.',
  ),

  // ── Productivity & Dev ────────────────────────────────────────────────────────
  AIIntegration(
    id: 'vercel',
    name: 'Vercel',
    description: 'Deploy frontend apps instantly with zero configuration.',
    url: 'https://vercel.com/dashboard',
    category: 'Developer',
    gradientColors: [0xFF18181B, 0xFF3F3F46],
    emoji: '▲',
    features: ['Deploy', 'Analytics', 'Edge Functions'],
    keywords: ['vercel', 'deploy', 'hosting', 'frontend', 'nextjs', 'edge', 'serverless'],
    searchUrlTemplate: 'https://vercel.com/dashboard',
    agentJsHint: "Click 'Add New' → 'Project' to deploy. Use the search bar for existing projects.",
  ),
  AIIntegration(
    id: 'supabase',
    name: 'Supabase',
    description: 'Open-source Firebase alternative — Postgres + Auth + Storage.',
    url: 'https://app.supabase.com',
    category: 'Developer',
    gradientColors: [0xFF3ECF8E, 0xFF1A7F5E],
    emoji: '🦋',
    features: ['Postgres', 'Auth', 'Storage'],
    keywords: ['supabase', 'database', 'postgres', 'auth', 'backend', 'api', 'tables'],
    searchUrlTemplate: 'https://app.supabase.com',
    agentJsHint: 'Navigate to your project. Use the SQL editor tab to run queries.',
  ),
  AIIntegration(
    id: 'msword',
    name: 'Word Online',
    description: 'Microsoft Word on the web — create and edit documents.',
    url: 'https://word.cloud.microsoft/',
    category: 'Productivity',
    gradientColors: [0xFF1F6FEB, 0xFF0D47A1],
    emoji: '📝',
    features: ['Documents', 'Templates', 'Collaboration'],
    keywords: ['word', 'microsoft word', 'docx', 'document', 'office', 'microsoft'],
    searchUrlTemplate: 'https://word.cloud.microsoft/',
    agentJsHint: "Click 'New blank document', type in the document editor.",
  ),

  // ── Social Media ──────────────────────────────────────────────────────────────
  AIIntegration(
    id: 'instagram',
    name: 'Instagram',
    description: 'Share photos, videos, Reels and connect with people.',
    url: 'https://www.instagram.com',
    category: 'Social',
    gradientColors: [0xFFE1306C, 0xFFF77737],
    emoji: '📸',
    features: ['Feed', 'Reels', 'Stories'],
    keywords: ['instagram', 'instagram post', 'reel', 'story', 'photo share', 'ig', 'follow'],
    searchUrlTemplate: 'https://www.instagram.com/explore/search/?q={query}',
    agentJsHint: 'Use the search icon to find users or hashtags. Click the + icon to create a post.',
  ),
  AIIntegration(
    id: 'whatsapp',
    name: 'WhatsApp Web',
    description: 'Message and call friends directly from JARVIS.',
    url: 'https://web.whatsapp.com',
    category: 'Social',
    gradientColors: [0xFF25D366, 0xFF128C7E],
    emoji: '💚',
    features: ['Messages', 'Calls', 'Groups'],
    keywords: ['whatsapp', 'message', 'chat', 'send message', 'whatsapp web', 'wa', 'group'],
    searchUrlTemplate: 'https://web.whatsapp.com',
    agentJsHint: 'Find contact by clicking search (magnifying glass). Click new chat, type message in input.',
  ),
  AIIntegration(
    id: 'telegram',
    name: 'Telegram',
    description: 'Fast and secure messaging — bots, channels and groups.',
    url: 'https://web.telegram.org/k/',
    category: 'Social',
    gradientColors: [0xFF2AABEE, 0xFF0088CC],
    emoji: '✈️',
    features: ['Channels', 'Bots', 'Groups'],
    keywords: ['telegram', 'tg', 'channel', 'bot', 'telegram message', 'group chat'],
    searchUrlTemplate: 'https://web.telegram.org/k/',
    agentJsHint: 'Click the search icon to find chats. Click a chat, type message in the input at the bottom.',
  ),
// ... Continuing kAIIntegrations array ...
  AIIntegration(
    id: 'github',
    name: 'GitHub',
    description: 'Code hosting, version control, and collaboration',
    category: 'Developer',
    url: 'https://github.com',
    gradientColors: [0xFF24292E, 0xFFFFFFFF],
    emoji: '🐙',
    features: ['Version Control', 'Repositories', 'Issues'],
    keywords: ['git', 'code', 'repo', 'repository', 'commit', 'pr'],
    searchUrlTemplate: 'https://github.com/search?q={query}',
    agentJsHint: '''
// GitHub Agent
if (command.includes('create repo')) {
  document.querySelector('a[href="/new"]')?.click();
} else if (command.includes('search')) {
  document.querySelector('.header-search-input')?.focus();
  document.querySelector('.header-search-input').value = command.split('search')[1].trim();
}
''',
  ),
  AIIntegration(
    id: 'canva',
    name: 'Canva',
    description: 'Create professional designs, presentations, and graphics',
    category: 'Design AI',
    url: 'https://www.canva.com',
    gradientColors: [0xFF00C4CC, 0xFF7D2AE8],
    emoji: '🎨',
    features: ['Presentations', 'Posters', 'Social Media'],
    keywords: ['design', 'graphic', 'presentation', 'art', 'banner'],
    searchUrlTemplate: 'https://www.canva.com/search?q={query}',
  ),
  AIIntegration(
    id: 'replit',
    name: 'Replit',
    description: 'Collaborative browser-based IDE and deployment',
    category: 'Developer',
    url: 'https://replit.com',
    gradientColors: [0xFFF26207, 0xFFF26207],
    emoji: '💻',
    features: ['Online IDE', 'Deployment', 'Collaboration'],
    keywords: ['replit', 'ide', 'code online', 'run code', 'deploy'],
    searchUrlTemplate: 'https://replit.com/search?q={query}',
  ),
  AIIntegration(
    id: 'lovable',
    name: 'Lovable AI',
    description: 'Build fully functional web apps with AI',
    category: 'Developer',
    url: 'https://lovable.dev',
    gradientColors: [0xFF8B5CF6, 0xFFEC4899],
    emoji: '❤️',
    features: ['AI Web Builder', 'React', 'Tailwind'],
    keywords: ['lovable', 'build app', 'web app', 'generate ui'],
    searchUrlTemplate: 'https://lovable.dev',
  ),
  AIIntegration(
    id: 'spotify',
    name: 'Spotify',
    description: 'Listen to music and podcasts',
    category: 'Productivity',
    url: 'https://open.spotify.com',
    gradientColors: [0xFF1DB954, 0xFF191414],
    emoji: '🎵',
    features: ['Music', 'Podcasts', 'Playlists'],
    keywords: ['music', 'song', 'play', 'track', 'album'],
    searchUrlTemplate: 'https://open.spotify.com/search/{query}',
  ),
  AIIntegration(
    id: 'gamma',
    name: 'Gamma AI',
    description: 'A new medium for presenting ideas with AI',
    category: 'Productivity',
    url: 'https://gamma.app',
    gradientColors: [0xFFFF7A00, 0xFFFF007A],
    emoji: '✨',
    features: ['Presentations', 'Documents', 'Webpages'],
    keywords: ['gamma', 'presentation', 'slide', 'deck', 'pitch'],
    searchUrlTemplate: 'https://gamma.app',
  ),
  AIIntegration(
    id: 'v0',
    name: 'v0 by Vercel',
    description: 'Generative UI system by Vercel',
    category: 'Developer',
    url: 'https://v0.dev',
    gradientColors: [0xFF000000, 0xFFFFFFFF],
    emoji: 'v0',
    features: ['React', 'Tailwind', 'Generative UI'],
    keywords: ['v0', 'vercel', 'generate ui', 'react component'],
    searchUrlTemplate: 'https://v0.dev/search?q={query}',
  ),
  AIIntegration(
    id: 'bolt',
    name: 'Bolt.new',
    description: 'Prompt, run, edit, and deploy full-stack web apps',
    category: 'Developer',
    url: 'https://bolt.new',
    gradientColors: [0xFF3B82F6, 0xFF10B981],
    emoji: '⚡',
    features: ['Full Stack', 'Deployment', 'WebContainers'],
    keywords: ['bolt', 'build fullstack', 'generate web', 'stackblitz'],
    searchUrlTemplate: 'https://bolt.new',
  ),

  // ── New AI Tools ──────────────────────────────────────────────────────────────
  AIIntegration(
    id: 'uizard',
    name: 'Uizard',
    description: 'Turn screenshots and sketches into UI designs with AI.',
    url: 'https://uizard.io',
    category: 'Design AI',
    gradientColors: [0xFF6C63FF, 0xFF48B2F5],
    emoji: '🧠',
    features: ['Wireframe to UI', 'Screenshot to Design', 'Themes'],
    keywords: ['uizard', 'wireframe', 'mockup', 'sketch to ui', 'ui from screenshot', 'design prototype', 'figma alternative'],
    searchUrlTemplate: 'https://uizard.io',
    agentJsHint: 'Click "New Project" or use the AI Generate button. Upload a screenshot or type a design prompt.',
  ),
  AIIntegration(
    id: 'popai',
    name: 'PopAI',
    description: 'AI-powered PDF analysis, presentation and document generation.',
    url: 'https://www.popai.pro',
    category: 'Productivity',
    gradientColors: [0xFF7B2FF7, 0xFFF107A3],
    emoji: '📊',
    features: ['PDF Chat', 'Slides', 'AI Search'],
    keywords: ['popai', 'pdf chat', 'talk to pdf', 'pdf analysis', 'presentation ai', 'slides ai', 'pop ai'],
    searchUrlTemplate: 'https://www.popai.pro',
    agentJsHint: 'Choose PDF mode to upload and chat with a document, or Presentation mode to generate slides.',
  ),
  AIIntegration(
    id: 'stitch',
    name: 'Google Stitch',
    description: 'Google\'s AI tool to design UI prototypes from text prompts.',
    url: 'https://stitch.withgoogle.com',
    category: 'Design AI',
    gradientColors: [0xFF4285F4, 0xFF0F9D58],
    emoji: '🧵',
    features: ['UI Prototyping', 'Prompt to UI', 'Google AI'],
    keywords: ['stitch', 'google stitch', 'ui prototype', 'figma prompt', 'design from prompt', 'google design ai'],
    searchUrlTemplate: 'https://stitch.withgoogle.com',
    agentJsHint: 'Type a UI design prompt and click Generate to produce a full UI prototype.',
  ),
  AIIntegration(
    id: 'quillbot',
    name: 'QuillBot',
    description: 'AI writing assistant — paraphrase, summarize, and grammar check.',
    url: 'https://quillbot.com',
    category: 'Writing AI',
    gradientColors: [0xFF00C98D, 0xFF0095FF],
    emoji: '✍️',
    features: ['Paraphrase', 'Summarize', 'Grammar Check'],
    keywords: ['quillbot', 'paraphrase', 'rewrite', 'rephrase', 'summarize', 'grammar', 'writing improve', 'plagiarism'],
    searchUrlTemplate: 'https://quillbot.com',
    agentJsHint: 'Paste text in the left panel, select mode (Paraphrase/Summarize), click button to process.',
  ),
  AIIntegration(
    id: 'lindy',
    name: 'Lindy AI',
    description: 'Build AI agents and automate workflows without code.',
    url: 'https://www.lindy.ai',
    category: 'Automation',
    gradientColors: [0xFF8B5CF6, 0xFF06B6D4],
    emoji: '🤖',
    features: ['AI Agents', 'Workflow Automation', 'No-Code'],
    keywords: ['lindy', 'lindy ai', 'ai agent', 'automate workflow', 'ai automation', 'no code automation', 'agent builder'],
    searchUrlTemplate: 'https://www.lindy.ai',
    agentJsHint: 'Create a new Lindy (agent) and define trigger + action steps.',
  ),
  AIIntegration(
    id: 'gumloop',
    name: 'Gumloop',
    description: 'Drag-and-drop AI workflow automation — connect apps with AI nodes.',
    url: 'https://www.gumloop.com',
    category: 'Automation',
    gradientColors: [0xFFFF6B6B, 0xFFFECA57],
    emoji: '🔄',
    features: ['Visual Automation', 'AI Nodes', 'App Connectors'],
    keywords: ['gumloop', 'workflow', 'automation', 'drag drop workflow', 'ai pipeline', 'app automation'],
    searchUrlTemplate: 'https://www.gumloop.com',
    agentJsHint: 'Create a new flow. Drag AI nodes onto canvas. Connect trigger → AI → action.',
  ),
  AIIntegration(
    id: 'n8n',
    name: 'n8n',
    description: 'Open-source workflow automation — connect anything with AI.',
    url: 'https://n8n.io',
    category: 'Automation',
    gradientColors: [0xFFEA4B71, 0xFF8B2FC9],
    emoji: '⛗️',
    features: ['Open Source', 'Self-Hosted', '400+ Integrations'],
    keywords: ['n8n', 'workflow automation', 'zapier alternative', 'self hosted automation', 'open source workflow'],
    searchUrlTemplate: 'https://n8n.io',
    agentJsHint: 'Add a new workflow. Use the + button to add nodes. Connect HTTP/Webhook to AI and output nodes.',
  ),
  AIIntegration(
    id: 'goblintools',
    name: 'Goblin Tools',
    description: 'Simple AI tools for people who struggle with executive function.',
    url: 'https://goblin.tools',
    category: 'Productivity',
    gradientColors: [0xFF4CAF50, 0xFF8BC34A],
    emoji: '👺',
    features: ['Task Breakdown', 'Tone Analyzer', 'Time Estimates'],
    keywords: ['goblin tools', 'task breakdown', 'adhd', 'executive function', 'task help', 'break down task', 'tone check'],
    searchUrlTemplate: 'https://goblin.tools',
    agentJsHint: 'Choose a tool (Magic ToDo/Estimator/etc). Type your task and click the goblin icon to process.',
  ),
];

/// Result of matching a user query to an integration
class IntegrationMatch {
  final AIIntegration integration;
  final String taskUrl;
  final String reason;

  const IntegrationMatch({
    required this.integration,
    required this.taskUrl,
    required this.reason,
  });
}

/// Matches a user query to the best integration and builds a task URL
IntegrationMatch? matchIntegration(String query, {Set<String>? connectedOnly}) {
  final lower = query.toLowerCase();
  AIIntegration? best;
  int bestScore = 0;

  final pool = connectedOnly != null
      ? kAIIntegrations.where((i) => connectedOnly.contains(i.id)).toList()
      : kAIIntegrations;

  for (final intg in pool) {
    int score = 0;
    for (final kw in intg.keywords) {
      if (lower.contains(kw)) score += kw.split(' ').length;
    }
    if (score > bestScore) {
      bestScore = score;
      best = intg;
    }
  }

  if (best == null || bestScore == 0) return null;

  final taskQuery = query
      .replaceAll(
          RegExp(r'(open|use|go to|launch|search on|via|with|using|in|on|at)\s+',
              caseSensitive: false),
          '')
      .trim();

  return IntegrationMatch(
    integration: best,
    taskUrl: best.buildTaskUrl(taskQuery),
    reason:
        'You asked about "${best.keywords.firstWhere((k) => lower.contains(k), orElse: () => best!.name)}"',
  );
}

/// Find integration by ID
AIIntegration? findIntegration(String id) {
  try {
    return kAIIntegrations.firstWhere((i) => i.id == id);
  } catch (_) {
    return null;
  }
}
