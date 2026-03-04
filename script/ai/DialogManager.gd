extends Node

const USE_BRIDGE := true
const BRIDGE_WORLD_ID := "poc1-world"
const BRIDGE_FALLBACK_PLAYER_TEXT := "Say something back to the player"

# 对话服务实例
var dialog_service: DialogService

# 当前设置（从SettingsManager获取）
var current_settings = {}

var dialog_bubble_scene = preload("res://scene/UI/DialogBubble.tscn")

# 兼容性变量（为了保持与现有代码的兼容性）
var current_speaker: CharacterBody2D = null
var current_listener: CharacterBody2D = null
var is_in_conversation = false

func _ready():
	# 创建对话服务
	dialog_service = DialogService.new()
	add_child(dialog_service)
	
	# 连接对话服务信号
	dialog_service.conversation_started.connect(_on_conversation_started)
	dialog_service.conversation_ended.connect(_on_conversation_ended)
	dialog_service.dialog_generated.connect(_on_dialog_generated)
	
	set_process_input(true)
	
	# 连接设置管理器
	SettingsManager.settings_changed.connect(_on_settings_changed)
	current_settings = SettingsManager.get_settings()
	print("[DialogManager] 已连接设置管理器和对话服务")

# 获取公司员工信息字符串
func get_company_employees_info() -> String:
	var employees_info = "\n\n公司员工名单及职位信息："
	
	# 遍历CharacterPersonality中的所有角色配置
	for character_name in CharacterPersonality.PERSONALITY_CONFIG:
		var personality = CharacterPersonality.PERSONALITY_CONFIG[character_name]
		employees_info += "\n- " + character_name + "：" + personality["position"]
	
	employees_info += "\n注意：在生成任何内容时，只能提及以上列出的员工，不要创造新的角色名字。"
	return employees_info

# 获取公司基本信息字符串
func get_company_basic_info() -> String:
	var company_info = "\n\n公司基本信息："
	company_info += "\n你们公司的主要产品是《CountSheep》小游戏。"
	company_info += "\n游戏宣传语：Can't Sleep? Count Sheep"
	company_info += "\n游戏玩法：通过让用户数手机屏幕上跳过的小羊，然后有九宫格数字按钮来计数得分。"
	company_info += "\n该游戏目前十分流行，吸引了许多跟时髦的小青年充值购买小羊皮肤和按键皮肤。"
	return company_info

# 获取角色详细状态信息
func get_character_status_info(character: CharacterBody2D) -> String:
	if not character:
		return "\n当前状态信息不可用。"
	
	# 从角色节点获取数据
	var money = character.get_meta("money", 0)
	var mood = character.get_meta("mood", "普通")
	var health = character.get_meta("health", "良好")
	var memories = character.get_meta("memories", [])
	var relations = character.get_meta("relations", {})
	
	var status_info = "\n\n【当前个人状态】"
	status_info += "\n💰 金钱：%d元" % money
	status_info += "\n😊 心情：%s" % mood
	status_info += "\n❤️ 健康：%s" % health
	
	status_info += "\n\n【记忆信息】"
	if memories.size() > 0:
		for i in range(min(3, memories.size())):
			status_info += "\n- " + memories[i]
	else:
		status_info += "\n- 暂无重要记忆"
	
	status_info += "\n\n【情感关系】"
	if relations.size() > 0:
		for person_name in relations:
			var relation = relations[person_name]
			var emotion_type = relation["type"] if relation.has("type") else "未知"
			var strength = relation["strength"] if relation.has("strength") else 0
			status_info += "\n- 与%s：%s (强度：%d)" % [person_name, emotion_type, strength]
	else:
		status_info += "\n- 暂无特殊情感关系"
	
	return status_info

# 处理输入事件
func _input(event):
	if event.is_action_pressed("start_dialog"):  # T键
		# 允许多组对话同时进行，不再检查is_in_conversation
		_try_start_conversation()
	elif event.is_action_pressed("end_dialog"):  # L键
		# 结束当前角色参与的对话，而不是所有对话
		_end_current_character_conversation()
	elif event.is_action_pressed("ui_cancel"):  # ESC键
		# 显示设置界面
		var settings_ui = get_node_or_null("/root/Office/SettingsUI")
		if settings_ui:
			settings_ui.toggle_settings_ui()

# 尝试开始对话
func _try_start_conversation():
	# 获取当前选中的角色
	var character_manager = get_node("/root/CharacterManager")
	if not character_manager or not character_manager.current_character:
		return
	
	# 获取当前选中角色附近的其他角色
	var nearby_character = character_manager.get_nearby_character(character_manager.current_character)
	if nearby_character:
		if USE_BRIDGE:
			await _try_start_bridge_conversation(character_manager.current_character, nearby_character)
			return

		# 使用新的对话服务开始对话
		var success = dialog_service.try_start_conversation(character_manager.current_character, nearby_character)
		if success:
			print("[DialogManager] 成功开始对话")
			# 为发起对话的角色添加记忆
			_add_memory_to_current_character(character_manager.current_character, "你主动与%s开始了对话。" % nearby_character.name)
			# 为被对话的角色也添加记忆
			_add_memory_to_current_character(nearby_character, "%s主动与你开始了对话。" % character_manager.current_character.name)
		else:
			print("[DialogManager] 无法开始对话")

func _try_start_bridge_conversation(player_character: CharacterBody2D, nearby_character: CharacterBody2D):
	if not get_node_or_null("/root/BridgeClient"):
		print("[DialogManager] BridgeClient不存在，跳过Bridge路径")
		return

	var npc_name = nearby_character.name.to_lower()
	var player_text = _resolve_bridge_player_text(player_character)
	var events = [{
		"type": "player_said",
		"player": player_character.name,
		"npc": npc_name,
		"text": player_text
	}]

	var batch_result = await BridgeClient.post_events_batch(BRIDGE_WORLD_ID, events)
	if not batch_result.get("ok", false):
		print("[DialogManager] Bridge事件提交失败：", batch_result)
		return

	var pull_result = await BridgeClient.pull_actions(BRIDGE_WORLD_ID)
	if not pull_result.get("ok", false):
		print("[DialogManager] Bridge动作拉取失败：", pull_result)
		return

	var data = pull_result.get("data", {})
	var actions: Array = []
	if data is Dictionary and data.get("actions", null) is Array:
		actions = data["actions"]

	if actions.is_empty():
		print("[DialogManager] Bridge未返回动作")
		return

	for action in actions:
		if not (action is Dictionary):
			continue

		if action.get("type", "") != "say":
			continue

		var action_npc_name = str(action.get("npc", "")).to_lower()
		var action_text = str(action.get("text", ""))
		var npc_node = _find_character_by_name_insensitive(action_npc_name)
		if not npc_node:
			npc_node = nearby_character

		_show_dialog_bubble(npc_node, action_text)
		print("[DialogManager] Bridge生成对话：%s 说：%s" % [npc_node.name, action_text])
		break

func _resolve_bridge_player_text(player_character: CharacterBody2D) -> String:
	# Prefer explicit player text if another UI flow stores it on the player node.
	var meta_keys = ["player_text", "last_player_text", "dialog_input_text", "latest_input_text"]
	for key in meta_keys:
		if player_character and player_character.has_meta(key):
			var meta_text = str(player_character.get_meta(key, "")).strip_edges()
			if not meta_text.is_empty():
				return meta_text

	# Fallback for POC-1 when no input dialog is wired yet.
	return BRIDGE_FALLBACK_PLAYER_TEXT

func _show_dialog_bubble(target_character: CharacterBody2D, dialog_text: String):
	if not target_character or dialog_text.is_empty():
		return

	var dialog_bubble = dialog_bubble_scene.instantiate()
	Engine.get_main_loop().root.add_child(dialog_bubble)
	dialog_bubble.target_node = target_character
	dialog_bubble.show_dialog(dialog_text)

# 结束当前角色参与的对话
func _end_current_character_conversation():
	var character_manager = get_node("/root/CharacterManager")
	if not character_manager or not character_manager.current_character:
		print("[DialogManager] 没有选中的角色")
		return
	# 在结束对话前，先为当前角色参与的所有对话添加结束记忆
	var current_character = character_manager.current_character
	var active_conversations = dialog_service.get_active_conversations_info()
	
	for conversation_info in active_conversations:
		var speaker_name = conversation_info["speaker"]
		var listener_name = conversation_info["listener"]
		
		# 如果当前角色参与了这个对话，为双方添加结束记忆
		if speaker_name == current_character.name or listener_name == current_character.name:
			_add_conversation_memory_to_participants(speaker_name, listener_name, "结束了对话")
   
	# 结束当前角色参与的所有对话
	dialog_service.end_character_conversations(current_character)
	print("[DialogManager] 已结束当前角色的对话")

# 结束所有对话（保留原函数用于其他地方调用）
func _end_conversation():
	# 如果有活跃的对话，结束所有对话
	if dialog_service.get_active_conversation_count() > 0:
		dialog_service.cleanup_all_conversations()
		print("[DialogManager] 已结束所有对话")
	else:
		print("[DialogManager] 当前没有活跃的对话")

# 查找最近的NPC
func _find_nearest_npc(player: Node2D) -> Node2D:
	var npcs = get_tree().get_nodes_in_group("npc")
	var nearest_distance = INF
	var nearest_npc = null
	
	for npc in npcs:
		var distance = player.global_position.distance_to(npc.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_npc = npc
	
	return nearest_npc

# 检查是否在对话范围内
func _is_in_range(node1: Node2D, node2: Node2D) -> bool:
	var max_dialog_distance = 100  # 可以根据需要调整对话距离
	return node1.global_position.distance_to(node2.global_position) <= max_dialog_distance

# 设置变化回调
func _on_settings_changed(new_settings: Dictionary):
	current_settings = new_settings.duplicate()
	print("[DialogManager] 设置已更新 - API类型：", current_settings.api_type, "，模型：", current_settings.model)

# 对话服务信号回调函数
func _on_conversation_started(conversation_id: String, speaker_name: String, listener_name: String):
	print("[DialogManager] 对话开始：%s <-> %s (ID: %s)" % [speaker_name, listener_name, conversation_id])
	
	# 添加对话开始记忆到参与者
	_add_conversation_memory_to_participants(speaker_name, listener_name, "开始了对话")
	
	# 更新兼容性变量（使用第一个活跃对话）
	var conversations = dialog_service.get_active_conversations_info()
	if conversations.size() > 0:
		is_in_conversation = true
		# 这里可以设置为最新的对话参与者，但由于支持多对话，这些变量的意义已经改变
		# 主要是为了保持与现有代话的兼容性

func _on_conversation_ended(conversation_id: String):
	print("[DialogManager] 对话结束：%s" % conversation_id)
	
	# 获取结束的对话信息并添加记忆
	_add_conversation_end_memory(conversation_id)
	
	# 更新兼容性变量
	if dialog_service.get_active_conversation_count() == 0:
		is_in_conversation = false
		current_speaker = null
		current_listener = null

func _on_dialog_generated(conversation_id: String, speaker_name: String, dialog_text: String):
	print("[DialogManager] 对话生成：%s 说：%s" % [speaker_name, dialog_text])

# 添加一些便利方法来访问对话服务功能
func get_active_conversation_count() -> int:
	return dialog_service.get_active_conversation_count() if dialog_service else 0

func get_active_conversations_info() -> Array:
	return dialog_service.get_active_conversations_info() if dialog_service else []

func is_character_in_conversation(character: CharacterBody2D) -> bool:
	return dialog_service.is_character_in_conversation(character) if dialog_service else false

func end_character_conversations(character: CharacterBody2D):
	if dialog_service:
		dialog_service.end_character_conversations(character)

# 添加对话开始记忆到参与者
func _add_conversation_memory_to_participants(speaker_name: String, listener_name: String, action: String):
	# 获取角色节点
	var speaker_node = _find_character_by_name(speaker_name)
	var listener_node = _find_character_by_name(listener_name)
	
	# 为说话者添加记忆
	if speaker_node:
		_add_memory_to_character(speaker_node, "你与%s%s。" % [listener_name, action])
	
	# 为听众添加记忆
	if listener_node:
		_add_memory_to_character(listener_node, "你与%s%s。" % [speaker_name, action])

# 添加对话结束记忆
func _add_conversation_end_memory(conversation_id: String):
	# 从对话服务获取对话信息（在对话结束前）
	var conversations_info = dialog_service.get_active_conversations_info()
	for conversation_info in conversations_info:
		if conversation_info["id"] == conversation_id:
			var speaker_name = conversation_info["speaker"]
			var listener_name = conversation_info["listener"]
			_add_conversation_memory_to_participants(speaker_name, listener_name, "结束了对话")
			break

# 根据名字查找角色节点
func _find_character_by_name(character_name: String) -> CharacterBody2D:
	var characters = get_tree().get_nodes_in_group("controllable_characters")
	for character in characters:
		if character.name == character_name:
			return character
	return null

func _find_character_by_name_insensitive(character_name: String) -> CharacterBody2D:
	var normalized_name = character_name.to_lower()
	var characters = get_tree().get_nodes_in_group("controllable_characters")
	for character in characters:
		if character.name.to_lower() == normalized_name:
			return character
	return null

# 添加记忆到角色
func _add_memory_to_character(character_node: CharacterBody2D, content: String):
	if not character_node:
		return
	
	# 获取character_data元数据
	var metadata = character_node.get_meta("character_data", {})
	if not metadata.has("memories"):
		metadata["memories"] = []
	
	# 添加记忆（使用字典格式，与_add_memory_to_current_character保持一致）
	metadata["memories"].append({
		"content": content,
		"timestamp": Time.get_unix_time_from_system()
	})
	character_node.set_meta("character_data", metadata)
	
	# 获取当前时间用于日志显示
	var current_time = Time.get_datetime_dict_from_system()
	var time_str = "%04d-%02d-%02d %02d:%02d" % [
		current_time.year, current_time.month, current_time.day,
		current_time.hour, current_time.minute
	]
	
	print("[DialogManager] 为%s添加记忆：[%s] %s" % [character_node.name, time_str, content])

# 添加记忆到当前角色（仿照AIAgent中的_add_memory方法）
func _add_memory_to_current_character(target_character, content: String):
	var metadata = target_character.get_meta("character_data", {})
	if not metadata.has("memories"):
		metadata["memories"] = []
	metadata["memories"].append({
		"content": content,
		"timestamp": Time.get_unix_time_from_system()
	})
	target_character.set_meta("character_data", metadata)
	print("[DialogManager] 为%s添加记忆：%s" % [target_character.name, content])
