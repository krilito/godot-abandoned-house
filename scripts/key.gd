extends Interactable

@export var key_name: String = "Basement Key"           # 钥匙名称
@export var key_description: String = "Secret door"    # 钥匙说明


func _ready() -> void:  # 初始化交互提示
	interaction_text = "E 拾取 " + key_name


func interact() -> void:  # 拾取钥匙
	PlayerInventory.add_item(key_name)
	queue_free()
