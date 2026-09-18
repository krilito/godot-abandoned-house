class_name Interactable
extends StaticBody3D


# ─────────────────────────────
# 交互参数
# ─────────────────────────────

@export_group("Interaction")

@export var interaction_text: String = "E 交互"   # 玩家看向物体时显示的提示


# ─────────────────────────────
# 交互行为
# ─────────────────────────────

func interact() -> void:
	print("Interact: ", name)                      # 默认行为：先用于测试交互是否成功


func get_interaction_text() -> String:
	return interaction_text                        # 把该物体自己的提示文字交给 Player
