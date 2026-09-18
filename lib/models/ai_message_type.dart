enum AiMessageType { chat, toolCall, toolResult }

enum AiMessageStatus {
  sending,
  sent,
  streaming,
  completed,
  failed,
  cancelled,
  interrupted,
}
