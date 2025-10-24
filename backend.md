# WarpBean Backend Documentation

## Overview

WarpBean是一个专为iOS应用设计的焦虑管理后端服务，提供AI驱动的建议生成和聊天功能。

**技术栈:**
- Node.js + Express.js
- MySQL数据库
- DeepSeek AI API集成
- JWT身份认证
- RESTful API设计

## Database Schema

### users 表
```sql
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(50) UNIQUE NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
```

### anxiety_topics 表
```sql
CREATE TABLE anxiety_topics (
  id INT PRIMARY KEY AUTO_INCREMENT,
  user_id INT NOT NULL,
  title VARCHAR(200) NOT NULL,
  description TEXT,
  severity_level ENUM('low', 'medium', 'high', 'critical') DEFAULT 'medium',
  status ENUM('active', 'resolved', 'archived') DEFAULT 'active',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### anxiety_suggestions 表
```sql
CREATE TABLE anxiety_suggestions (
  id INT PRIMARY KEY AUTO_INCREMENT,
  topic_id INT NOT NULL,
  user_id INT NOT NULL,
  suggestion_text TEXT NOT NULL,
  suggestion_type ENUM('immediate', 'short_term', 'long_term', 'professional') DEFAULT 'immediate',
  is_helpful BOOLEAN DEFAULT NULL,
  helpful_rating INT CHECK (helpful_rating >= 1 AND helpful_rating <= 5),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (topic_id) REFERENCES anxiety_topics(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### chat_conversations 表
```sql
CREATE TABLE chat_conversations (
  id INT PRIMARY KEY AUTO_INCREMENT,
  user_id INT NOT NULL,
  title VARCHAR(200),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### chat_messages 表
```sql
CREATE TABLE chat_messages (
  id INT PRIMARY KEY AUTO_INCREMENT,
  conversation_id INT NOT NULL,
  user_id INT NOT NULL,
  message_text TEXT NOT NULL,
  message_type ENUM('user', 'assistant') NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

## API Endpoints

### 认证相关 (Authentication)

#### POST /api/auth/register
用户注册
```json
// Request
{
  "username": "testuser",
  "email": "test@example.com",
  "password": "TestPassword123"
}

// Response
{
  "success": true,
  "message": "User registered successfully",
  "data": {
    "user": {
      "id": 1,
      "username": "testuser",
      "email": "test@example.com"
    },
    "token": "jwt_token_here"
  }
}
```

#### POST /api/auth/login
用户登录
```json
// Request
{
  "username": "testuser",
  "password": "TestPassword123"
}

// Response
{
  "success": true,
  "message": "Login successful",
  "data": {
    "user": {
      "id": 1,
      "username": "testuser",
      "email": "test@example.com"
    },
    "token": "jwt_token_here"
  }
}
```

### 建议生成相关 (Suggestions)

#### POST /api/suggestion
生成焦虑建议 (需要认证)
```json
// Request
{
  "title": "我想减肥",
  "description": "最近体重增加了很多，感到很焦虑",
  "severity_level": "medium",
  "personality": "green"  // 可选: "green", "yellow", "red"
}

// Response
{
  "success": true,
  "message": "Suggestions generated successfully",
  "data": {
    "topic": {
      "id": 1,
      "title": "我想减肥",
      "description": "最近体重增加了很多，感到很焦虑",
      "severity_level": "medium"
    },
    "suggestions": [
      {
        "id": 1,
        "suggestion_text": "欸～又想起减肥啦？别慌，这事不催你～先深呼吸，Cobean在这儿陪着你🌿",
        "suggestion_type": "immediate"
      }
    ],
    "personality": "green",
    "usage": {
      "prompt_tokens": 648,
      "completion_tokens": 285,
      "total_tokens": 933
    }
  }
}
```

#### POST /api/suggestion-test/generate
测试建议生成 (无需认证)
```json
// Request
{
  "title": "我想减肥",
  "personality": "yellow"  // 可选: "green", "yellow", "red"
}

// Response
{
  "success": true,
  "message": "Suggestions generated successfully",
  "suggestions": [
    {
      "text": "嘿～又想到那件事啦？要不咱今天就先写一点点，五分钟也算打怪升级呀💪😉",
      "type": "立即行动（黄泡版）"
    }
  ],
  "personality": "yellow",
  "usage": {
    "prompt_tokens": 648,
    "completion_tokens": 285,
    "total_tokens": 933
  },
  "timestamp": "2025-10-22T09:53:07.682Z"
}
```

#### POST /api/suggestion-test/public/generate
公开建议生成接口 (无需认证)
```json
// Request
{
  "title": "工作压力大",
  "personality": "yellow",  // 可选: "green", "yellow", "red"
  "history": [  // 可选: 历史建议记录数组
    {
      "suggestion_text": "先深呼吸，放松一下",
      "suggestion_type": "立即行动"
    },
    {
      "suggestion_text": "和朋友聊聊天，分享压力",
      "suggestion_type": "社交支持"
    }
  ]
}

// Response
{
  "success": true,
  "message": "Public suggestions generated successfully",
  "suggestions": [
    {
      "text": "嘿～工作小怪兽又在捣乱啦？别让它吓到你～今天先列出三件紧急的小事，搞定一个就给自己点个赞🌼",
      "type": "实质反馈"
    }
  ],
  "personality": "yellow",
  "history_count": 2,
  "timestamp": "2025-10-23T08:02:57.454Z"
}
```

#### POST /api/suggestion-test/test-multiple
批量测试多个主题 (无需认证)
```json
// Request
{
  "personality": "red"  // 可选: "green", "yellow", "red"
}

// Response
{
  "success": true,
  "message": "Multiple topic test completed with red personality",
  "results": [
    {
      "topic": "我想减肥",
      "success": true,
      "suggestions": [...],
      "usage": {...},
      "personality": "red"
    }
  ],
  "personality": "red",
  "timestamp": "2025-10-22T09:53:07.682Z"
}
```

#### GET /api/suggestion/topics
获取用户的焦虑主题列表 (需要认证)

#### GET /api/suggestion/topics/:id
获取特定主题的详细信息 (需要认证)

#### GET /api/suggestion/history
获取用户的建议历史 (需要认证)

#### POST /api/suggestion/feedback/:id
提交建议反馈 (需要认证)
```json
// Request
{
  "is_helpful": true,
  "helpful_rating": 4
}
```

#### GET /api/suggestion/stats
获取用户统计信息 (需要认证)

### 聊天相关 (Chat)

#### POST /api/chat
发送聊天消息 (需要认证)
```json
// Request
{
  "message": "我今天感到很焦虑",
  "conversation_id": 1
}

// Response
{
  "success": true,
  "message": "Chat response generated successfully",
  "data": {
    "conversation_id": 1,
    "user_message": {
      "id": 1,
      "message_text": "我今天感到很焦虑",
      "message_type": "user"
    },
    "assistant_message": {
      "id": 2,
      "message_text": "欸～感到焦虑了呀？别慌，我在这儿陪着你🌿",
      "message_type": "assistant"
    }
  }
}
```

### 健康检查 (Health Check)

#### GET /health
服务器健康检查
```json
// Response
{
  "status": "OK",
  "timestamp": "2025-10-22T09:53:07.682Z",
  "uptime": 7.71052475
}
```

#### GET /api/suggestion-test/health
建议服务健康检查 (无需认证)
```json
// Response
{
  "status": "OK",
  "service": "suggestion",
  "deepseek": {
    "success": true,
    "status": "healthy",
    "model": "deepseek-chat"
  },
  "timestamp": "2025-10-22T09:53:07.682Z"
}
```

## Project Structure

```
warpbean-backend/
├── src/
│   ├── config/
│   │   └── database.js          # 数据库配置
│   ├── middleware/
│   │   ├── auth.js              # JWT认证中间件
│   │   └── errorHandler.js      # 错误处理中间件
│   ├── models/
│   │   ├── User.js              # 用户模型
│   │   ├── AnxietyTopic.js      # 焦虑主题模型
│   │   ├── AnxietySuggestion.js # 建议模型
│   │   ├── ChatConversation.js  # 聊天会话模型
│   │   └── ChatMessage.js       # 聊天消息模型
│   ├── routes/
│   │   ├── auth.js              # 认证路由
│   │   ├── suggestion.js        # 建议路由 (需认证)
│   │   ├── suggestion_test.js   # 测试建议路由 (无需认证)
│   │   └── chat.js              # 聊天路由
│   ├── services/
│   │   └── deepseekService.js   # DeepSeek AI服务
│   ├── utils/
│   │   └── validation.js        # 验证工具
│   └── app.js                   # 主应用文件
├── .env                         # 环境变量
├── package.json                 # 项目依赖
└── server.js                    # 服务器启动文件
```

## Setup & Deployment Guide

### 环境要求
- Node.js 16+
- MySQL 8.0+
- DeepSeek API密钥

### 安装步骤

1. **克隆项目**
```bash
git clone <repository-url>
cd warpbean-backend
```

2. **安装依赖**
```bash
npm install
```

3. **配置环境变量**
创建 `.env` 文件：
```env
# 服务器配置
PORT=3000
NODE_ENV=development

# 数据库配置
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=your_password
DB_NAME=warpbean

# JWT配置
JWT_SECRET=your_jwt_secret
JWT_EXPIRES_IN=24h

# DeepSeek API配置
DEEPSEEK_API_KEY=your_deepseek_api_key
DEEPSEEK_BASE_URL=https://api.deepseek.com

# CORS配置
CORS_ORIGIN=*

# 限流配置
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

4. **数据库设置**
```bash
# 创建数据库
mysql -u root -p
CREATE DATABASE warpbean;

# 运行迁移脚本 (如果有)
npm run migrate
```

5. **启动服务**
```bash
# 开发模式
npm run dev

# 生产模式
npm start
```

### 测试

#### 完整API测试 (需要数据库)
```bash
# 确保MySQL服务运行
brew services start mysql

# 运行完整测试
npm test
```

#### 无数据库测试 (仅测试AI功能)
访问测试端点：
- `GET /api/suggestion-test/health` - 服务健康检查
- `POST /api/suggestion-test/generate` - 单个建议生成
- `POST /api/suggestion-test/test-multiple` - 批量建议测试

#### 人格功能测试
使用专门的人格测试脚本：
```bash
# 运行人格API测试
node test_personality_api.js
```

测试内容包括：
- 三种人格的单个建议生成测试
- 三种人格的多主题批量测试
- 服务健康状态检查
- API响应格式验证

## AI Integration

### DeepSeek服务配置

WarpBean支持三种不同的AI人格，每种人格都有独特的语气和回复风格：

#### 绿色人格 (Green Personality) - 默认
**特征:**
- 温柔、俏皮、有一点懒洋洋的可爱气质
- 使用"欸～""嘿～""哎呀～"等抚慰语句
- 支持emoji表情 (🌿、😌、😉、😏、🐈、💭、😁)
- 40-80字的自然口语化回复
- 目标：让用户感到被理解和接纳，降低焦虑感

**方法论支持:**
1. 长期主义 → "不需要现在搞定""时间够"
2. 不比较 → "别和别人比"
3. 实质反馈 → "能想起就值得被肯定"
4. 明确需求 → "关注现在最重要的小事"
5. 立即行动（绿泡版）→ "允许不做，先歇一会儿"
6. 课题分离 → "放下不在你掌控的事"

#### 黄色人格 (Yellow Personality)
**特征:**
- 调皮又鼓励人的小精灵，语气轻快、温暖、带一点行动的能量
- 使用"嘿～""哎呀～""来嘛～""要不咱试试～"等引导语句
- 支持轻emoji表情 (😉🌼✏️💪😏✨🐝)，不超过两个
- 40-80字的自然口语化回复
- 目标：让用户产生"其实我可以先动一点点"的意愿

**方法论支持:**
1. 实质反馈 → "从小事做起，完成后给自己一个肯定"
2. 明确需求 → "想想什么对你才是真正重要的"
3. 立即行动（黄泡版）→ "先开始做五分钟，往往就不那么难了"
4. 长期主义 → "成长要时间，今天的小动作也算进步"
5. 不比较 → "别看别人啦～你自己的节奏就挺好"
6. 课题分离 → "只动你能动的，其他让它去吧～"

#### 红色人格 (Red Personality)
**特征:**
- 稳定、笃定、有安全感的引导者，稳重、低语、肯定
- 不带焦躁，不讲大道理，不空洞安慰，不使用调皮语气
- 使用"短句 + 停顿感"给用户"被接住"的感觉
- 可选emoji (🌿💪💭)，不超过一个
- 40-80字的自然口语化回复
- 目标：让用户情绪降温，从"全局混乱"回到"可控的一点"

**方法论支持:**
1. 课题分离 → "只管你能控制的部分"
2. 明确需求 → "想清楚现在最重要的一件事"
3. 立即行动 → "先动一点，再慢慢理"
4. 长期主义（稳态）→ "事情需要时间，不要催自己"
5. 实质反馈 → "能觉察焦虑本身就是进步"
6. 不比较 → "别和别人比，你有你自己的节奏"

### 人格选择参数
在所有建议生成API中，可以通过 `personality` 参数选择使用的人格：
- `"green"` (默认) - 绿色人格
- `"yellow"` - 黄色人格  
- `"red"` - 红色人格

### API使用统计
每次AI调用都会返回token使用情况：
- `prompt_tokens`: 输入token数
- `completion_tokens`: 输出token数
- `total_tokens`: 总token数

## Changelog

### 2025-10-23
- **新增**: 公开建议生成接口 `POST /api/suggestion-test/public/generate`
- **功能**: 无需身份验证即可获取AI建议，支持三种人格选择
- **用途**: 为未注册用户或演示场景提供建议生成服务
- **安全**: 保持与测试接口相同的验证和限流机制
- **增强**: 公开接口新增 `history` 参数支持
- **功能**: 可选的历史建议记录数组，AI会基于历史记录生成不重复的新建议
- **验证**: 完整的参数验证，确保history数组中每个项目包含必需字段
- **响应**: 新增 `history_count` 字段，显示传入的历史记录数量

### 2025-10-22
- **新增**: 三种AI人格支持 - 绿色(默认)、黄色、红色人格
- **新增**: `personality` 参数支持，可在所有建议生成API中选择人格类型
- **新增**: 黄色人格 - 调皮鼓励型，轻快温暖，引导用户轻松行动
- **新增**: 红色人格 - 稳定引导型，稳重笃定，帮助用户情绪降温
- **更新**: `src/services/deepseekService.js` - 重构支持多人格切换
- **更新**: `src/routes/suggestion.js` - 添加personality参数验证和处理
- **更新**: `src/routes/suggestion_test.js` - 测试路由支持人格参数
- **新增**: `test_personality_api.js` - 专门的人格功能测试脚本
- **文档**: 完善API文档，详细描述三种人格的特征和使用方法
- **新增**: 创建 `suggestion_test.js` 路由，提供无需认证的建议生成测试接口
- **新增**: `/api/suggestion-test/generate` - 单个建议生成测试端点
- **新增**: `/api/suggestion-test/test-multiple` - 批量主题测试端点
- **新增**: `/api/suggestion-test/health` - 建议服务健康检查端点
- **修复**: DeepSeek响应解析逻辑，支持多种JSON格式
- **优化**: 添加详细的调试日志，便于问题排查
- **测试**: 验证了Cobean绿色人格的AI提示词效果，成功生成符合要求的建议

### 2025-10-21
- **更新**: 调整DeepSeek提示词，优化Cobean绿色人格特征
- **优化**: 改进建议生成的语气和内容质量
- **测试**: 完成AI提示词效果验证

### 2025-10-20
- **初始化**: 项目基础架构搭建
- **完成**: 用户认证系统实现
- **完成**: 建议生成API开发
- **完成**: 聊天功能实现
- **完成**: 数据库模型设计