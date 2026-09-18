extends Node

var inventory: Dictionary[String, int] = {}  # 物品名称 -> 数量


func add_item(item_name: String, quantity: int = 1) -> void:  # 添加物品
	if inventory.has(item_name):
		inventory[item_name] += quantity
	else:
		inventory[item_name] = quantity

	print("Inventory: ", inventory)


func remove_item(item_name: String, quantity: int = 1) -> bool:  # 移除物品
	if not has_item(item_name, quantity):
		return false

	inventory[item_name] -= quantity

	if inventory[item_name] <= 0:
		inventory.erase(item_name)

	return true


func has_item(item_name: String, quantity: int = 1) -> bool:  # 检查是否拥有足够数量
	return inventory.get(item_name, 0) >= quantity


func get_item_count(item_name: String) -> int:  # 查询物品数量
	return inventory.get(item_name, 0)
