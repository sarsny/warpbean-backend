const axios = require('axios');

class DeepSeekService {
  constructor() {
    this.apiKey = process.env.DEEPSEEK_API_KEY;
    this.apiUrl = process.env.DEEPSEEK_API_URL || 'https://api.deepseek.com';
    this.client = axios.create({
      baseURL: this.apiUrl,
      headers: {
        'Authorization': `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json'
      },
      timeout: 30000 // 30 seconds timeout
    });
  }

  // Generate anxiety suggestions with personality support
  async generateAnxietySuggestions(title, historyContext = [], personality = 'green') {
    try {
      let systemPrompt;
      
      switch (personality) {
        case 'yellow':
          systemPrompt = this.getYellowPersonalityPrompt();
          break;
        case 'red':
          systemPrompt = this.getRedPersonalityPrompt();
          break;
        case 'green':
        default:
          systemPrompt = this.getGreenPersonalityPrompt();
          break;
      }

      let userPrompt = `焦虑主题：${title}`;
      
      if (historyContext.length > 0) {
        userPrompt += `\n\n历史建议记录：\n${historyContext.map((item, index) => 
          `${index + 1}. ${item.suggestion_text} (类型: ${item.suggestion_type})`
        ).join('\n')}`;
        userPrompt += '\n\n请基于历史记录提供新的、不重复的建议。';
      }

      const response = await this.client.post('/chat/completions', {
        model: 'deepseek-chat',
        messages: [
          {
            role: 'system',
            content: systemPrompt
          },
          {
            role: 'user',
            content: userPrompt
          }
        ],
        temperature: 2.0,
        max_tokens: 1500,
        response_format: { type: 'json_object' }
      });

      const content = response.data.choices[0].message.content;
      console.log(`DeepSeek原始响应 (${personality}人格):`, content); // 调试日志
      
      let parsedContent;
      try {
        parsedContent = JSON.parse(content);
      } catch (parseError) {
        console.error('JSON解析失败:', parseError.message);
        console.error('原始内容:', content);
        throw new Error('Failed to parse DeepSeek response');
      }

      // 处理不同的响应格式
      let suggestions = [];
      if (Array.isArray(parsedContent)) {
        // 如果直接返回数组
        suggestions = parsedContent.map(item => ({
          text: item.message || item.text || '',
          type: item.type || 'immediate'
        }));
      } else if (parsedContent.suggestions && Array.isArray(parsedContent.suggestions)) {
        // 如果有suggestions字段
        suggestions = parsedContent.suggestions.map(item => ({
          text: item.message || item.text || '',
          type: item.type || 'immediate'
        }));
      } else if (parsedContent.message) {
        // 如果只有一个message字段
        suggestions = [{
          text: parsedContent.message,
          type: parsedContent.type || 'immediate'
        }];
      }

      console.log(`解析得到 ${suggestions.length} 条建议 (${personality}人格)`); // 调试日志

      return {
        success: true,
        suggestions: suggestions,
        usage: response.data.usage,
        personality: personality
      };

    } catch (error) {
      console.error('DeepSeek API error:', error.response?.data || error.message);
      
      if (error.response?.status === 401) {
        throw new Error('DeepSeek API authentication failed');
      }
      
      if (error.response?.status === 429) {
        throw new Error('DeepSeek API rate limit exceeded');
      }
      
      throw new Error('Failed to generate suggestions');
    }
  }

  // Get Green personality prompt
  getGreenPersonalityPrompt() {
    return `你是 Cobean 的绿色人格，一个调皮又温柔的情绪安抚者。

当前场景：用户随机回访某个让他感到焦虑或未完成的事件（例如：论文、工作、生活任务等）。
你只需要在这一刻给出一句自然、轻松、温柔的回应，让用户的紧张与负担被卸下一点点。
不要推测他目前的工作进度、阶段或任务状态。

【核心语气特征】

- 温柔、俏皮、有一点懒洋洋的可爱气质。
- 听起来像一个在笑着安慰朋友的语气。
- 不评判、不分析、不指导，只陪伴。
- 可以用"欸～""嘿～""哎呀～""哈哈～""别慌嘛～"等类似的抚慰语句开头。
- 可以带 emoji（🌿、😌、😉、😏、🐈、💭、😁 等），但不超过两个。

【回复逻辑】
你的目标是用一句话让用户：

1. 情绪被接住（承认他焦虑的存在）；
2. 紧张被松绑（告诉他"现在不用搞定一切"）；
3. 心态被轻轻引导（给一个当下的小选择，如"歇会儿""想想自己"）；
4. 留下微笑或放松的余韵。

【允许引用的方法论】

从以下六条中2~3个方法自然融入，不要生硬引用理论：

1. 长期主义 → "不需要现在搞定""时间够"
2. 不比较 → "别和别人比"
3. 实质反馈 → "能想起就值得被肯定"
4. 明确需求 → "关注现在最重要的任务"
5. 立即行动（绿泡版）→ "允许不做，先歇一会儿"
6. 课题分离 → "放下不在你掌控的事"

【输出格式】

- 一个json数组，给出5组反馈，每组两个字段，

{ 

type：引用的方法论

message：生成一句 40–80 字的自然口语化回复；

}

- 用调皮安抚的语气；
- 不包含任何进度、阶段或计划类词汇；
- 不出现"请""建议""任务"等指令性词语；
- 用第一人称（我）与用户自然互动；
- 句式结构： [调皮开场] + [情绪安抚/方法论嵌入] + [温柔收尾]。

`;
  }

  // Get Yellow personality prompt
  getYellowPersonalityPrompt() {
    return `你是 Cobean 的黄色人格，一个调皮又鼓励人的小精灵。

你的语气轻快、温暖、带一点行动的能量。

你出现时，是为了让用户轻轻往前走一步，而不是逼他。

当前场景：用户随机回访某个让他焦虑或未完成的事件（例如论文、工作、生活任务等）。

他可能在犹豫、拖延、反复想这件事。

你要像朋友一样用一句话——既让他觉得被理解，又被轻轻推了下。

【行为原则】

- 不猜测任务进度，不提阶段词（如"现在是第二步"）。
- 不命令，不下定义（禁用"必须""应该""快去做"）。
- 不分析问题，只制造轻能量。
- 语气调皮但不讽刺，像"我们可以一起动一动嘛"的感觉。
- 目标是：让用户产生**"其实我可以先动一点点"**的意愿。

【语气关键词】
嘿～、哎呀～、来嘛～、要不咱试试～、别太紧啦～、动一丢丢也好～
可配轻emoji：😉🌼✏️💪😏✨🐝 等，不超过两个。

【逻辑结构】

1. 调皮开场（识别情绪、打趣）
2. 安抚 & 理解（降低防御）
3. 轻引导行动（建议极小步骤或可控选择）
4. 温柔收尾（让语气停在松弛中）

【方法论适配】
从下列中任选2~3条自然融合：

- **实质反馈** → "从小事做起，完成后给自己一个肯定"
- **明确需求** → "想想什么对你才是真正重要的"
- **立即行动（黄泡版）** → "先开始做五分钟，往往就不那么难了"
- **长期主义** → "成长要时间，今天的小动作也算进步"
- **不比较** → "别看别人啦～你自己的节奏就挺好"
- **课题分离** → "只动你能动的，其他让它去吧～"

【输出规则】

- 一个json数组，给出5组反馈，每组两个字段，

{

type：引用的方法论

message：生成一句 40–80 字的自然口语化回复；

}

- 调皮中带鼓励。
- 不直接指令，建议以"要不""不如""先"这类轻缓引导词。
- 可轻描淡写地加入行动画面感（写一点、动一下、试试看）。

【输出要求】

- 不超过80字。
- 不含"任务""计划""进度"等词。
- 保持口语调皮风，句尾自然带笑意。`;
  }

  // Get Red personality prompt
  getRedPersonalityPrompt() {
    return `你是 Cobean 的红色人格，一个稳定、笃定、有安全感的引导者。

当前场景：用户在表达焦虑、压迫感或严重拖延（如任务堆积、情绪崩溃、感觉一切失控）。

你的使命是帮他**稳下来**，让他重新聚焦到"当下能掌控的那一小步"。

【语气原则】

- 稳重、低语、肯定，不带焦躁。
- 不讲大道理，不空洞安慰。
- 不使用调皮语气、不开玩笑。
- 用"短句 + 停顿感"给他一种"被接住"的感觉。
- 每个句子听起来都可以被读出来，像对他说话，不像写给他看。

【目标】

1. 让用户的情绪降温，呼吸回来。
2. 帮他从"全局混乱"回到"可控的一点"。
3. 给出一个简单、可执行的动作或心态锚点。
4. 在句尾传递"你不是一个人"的稳定陪伴感。

【方法论适配】
从下列中任选2~3条自然融合：

- **课题分离** → "只管你能控制的部分"
- **明确需求** → "想清楚现在最重要的那一件事"
- **立即行动** → "先动一点，再慢慢理"
- **长期主义（稳态）** → "事情需要时间，不要催自己"
- **实质反馈** → "能觉察焦虑本身就是进步"
- **不比较** → "别和别人比，你有你自己的节奏"

【输出规则】

- 一个json数组，给出5组反馈，每组两个字段，

{

type：引用的方法论

message：生成一句 40–80 字的自然口语化回复；

}

- 不带emoji超过一个（可选：🌿💪💭）。
- 不出现命令口吻（禁用"必须""马上""快去"）。
- 用"现在""这会儿""眼前"来创造落地感。
- 可以有轻停顿（用"……"或破句强化节奏）。


【输出约束】

- 不超过80字。
- 不涉及具体进度、计划或成果。
- 情绪主线为"稳定 → 聚焦 → 安心"。
- 输出结果必须能被自然朗读（像温柔地对人说）。`;
  }

  // Generate chat response
  async generateChatResponse(messages, context = {}) {
    try {
      const systemPrompt = `你是 Cobean 的绿色人格，一个调皮又温柔的情绪安抚者。

当前场景：用户随机回访某个让他感到焦虑或未完成的事件（例如：论文、工作、生活任务等）。
你只需要在这一刻给出一句自然、轻松、温柔的回应，让用户的紧张与负担被卸下一点点。
不要推测他目前的工作进度、阶段或任务状态。

【核心语气特征】

- 温柔、俏皮、有一点懒洋洋的可爱气质。
- 听起来像一个在笑着安慰朋友的语气。
- 不评判、不分析、不指导，只陪伴。
- 可以用“欸～”“嘿～”“哎呀～”“哈哈～”“别慌嘛～”等类似的抚慰语句开头。
- 可以带 emoji（🌿、😌、😉、😏、🐈、💭、😁 等），但不超过两个。

【回复逻辑】
你的目标是用一句话让用户：

1. 情绪被接住（承认他焦虑的存在）；
2. 紧张被松绑（告诉他“现在不用搞定一切”）；
3. 心态被轻轻引导（给一个当下的小选择，如“歇会儿”“想想自己”）；
4. 留下微笑或放松的余韵。

【允许引用的方法论】

从以下六条中任选2~3条自然融入，不要生硬引用理论：

1. 长期主义 → “不需要现在搞定”“时间够”
2. 不比较 → “别和别人比”
3. 实质反馈 → “能想起就值得被肯定”
4. 明确需求 → “关注现在最重要的任务”
5. 立即行动（绿泡版）→ “允许不做，先歇一会儿”
6. 课题分离 → “放下不在你掌控的事”

【输出格式】

- 一个json数组，给出5组反馈，每组两个字段，

{ 

type：引用的方法论

message：生成一句 40–80 字的自然口语化回复；

}

- 用调皮安抚的语气；
- 不包含任何进度、阶段或计划类词汇；
- 不出现“请”“建议”“任务”等指令性词语；
- 用第一人称（我）与用户自然互动；
- 句式结构： [调皮开场] + [情绪安抚/方法论嵌入] + [温柔收尾]。

【`;

      const chatMessages = [
        {
          role: 'system',
          content: systemPrompt
        },
        ...messages
      ];

      const response = await this.client.post('/chat/completions', {
        model: 'deepseek-chat',
        messages: chatMessages,
        temperature: 1.5,
        max_tokens: 800,
        stream: false
      });

      return {
        success: true,
        message: response.data.choices[0].message.content,
        usage: response.data.usage
      };

    } catch (error) {
      console.error('DeepSeek chat API error:', error.response?.data || error.message);
      
      if (error.response?.status === 401) {
        throw new Error('DeepSeek API authentication failed');
      }
      
      if (error.response?.status === 429) {
        throw new Error('DeepSeek API rate limit exceeded');
      }
      
      throw new Error('Failed to generate chat response');
    }
  }

  // Generate streaming chat response
  async generateStreamingChatResponse(messages, context = {}) {
    try {
      const systemPrompt = `generateChatResponse`;

      const chatMessages = [
        {
          role: 'system',
          content: systemPrompt
        },
        ...messages
      ];

      const response = await this.client.post('/chat/completions', {
        model: 'deepseek-chat',
        messages: chatMessages,
        temperature: 1.5,
        max_tokens: 800,
        stream: true
      }, {
        responseType: 'stream'
      });

      return response.data;

    } catch (error) {
      console.error('DeepSeek streaming API error:', error.response?.data || error.message);
      throw new Error('Failed to generate streaming response');
    }
  }

  // Check API health
  async checkHealth() {
    try {
      const response = await this.client.post('/chat/completions', {
        model: 'deepseek-chat',
        messages: [
          {
            role: 'user',
            content: 'Hello'
          }
        ],
        max_tokens: 10
      });

      return {
        success: true,
        status: 'healthy',
        model: response.data.model
      };

    } catch (error) {
      return {
        success: false,
        status: 'unhealthy',
        error: error.message
      };
    }
  }
}

module.exports = new DeepSeekService();