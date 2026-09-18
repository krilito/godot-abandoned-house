@tool
extends McpTestSuite

## Casa/Puerta 开门动画数据回归测试（编辑器层）。
## door.gd 的运行时行为需要真实游戏进程验证（非 @tool 脚本在编辑器里是 placeholder），
## 本套件只断言 abandoned_house.tscn 中保存的动画数据结构与场景接线。


const CLOSE_ROTATION := Vector3(PI, 0.0, 0.0)      # Puerta 关闭时的真实欧拉角
const OPEN_ROTATION := Vector3(PI, -PI / 2.0, 0.0) # 绕 Y 轴 -90° 后的目标角
const ANIM_LENGTH := 0.8


var _mesh: Node3D
var _door: Node
var _anim: AnimationPlayer


func suite_name() -> String:
	return "door"


func setup() -> void:
	var house: Node = (load("res://abandoned_house.tscn") as PackedScene).instantiate()
	track(house)
	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(house)
	_mesh = house.get_node("Casa/Puerta")
	_door = _mesh.get_node("Collision_Puerta")
	_anim = _mesh.get_node("AnimationPlayer")


func test_door_wiring() -> void:
	assert_true(_anim is AnimationPlayer, "Puerta 下必须有 AnimationPlayer")
	assert_ne(_mesh.get_child_count(), 0, "Collision_Puerta 应是 Puerta 的子节点")
	assert_eq(_door.get_parent(), _mesh, "门碰撞体必须保持父子关系（随门旋转）")
	assert_true(_door.get_script() != null, "Collision_Puerta 应挂有 door.gd")


func test_saved_animation_data() -> void:
	var anim: Animation = _anim.get_animation("open")
	assert_ne(anim, null, "open 动画必须存在于场景中")
	assert_true(is_equal_approx(anim.length, ANIM_LENGTH), "动画时长应为 0.8s")
	assert_eq(anim.loop_mode, Animation.LOOP_NONE, "不得循环播放")
	assert_eq(anim.get_track_count(), 1, "只允许一条动画轨道")
	assert_eq(str(anim.track_get_path(0)), ".:rotation", "轨道只修改 Puerta 自身旋转")
	assert_eq(anim.track_get_key_count(0), 2, "两个关键帧")
	assert_true(anim.track_get_key_value(0, 0).is_equal_approx(CLOSE_ROTATION), "首帧=当前关闭姿态")
	assert_true(anim.track_get_key_value(0, 1).is_equal_approx(OPEN_ROTATION), "末帧=Y 轴 -90°")
	assert_true(is_equal_approx(anim.track_get_key_time(0, 1), ANIM_LENGTH), "末帧在 0.8s")


func test_scene_starts_closed_without_autoplay() -> void:
	assert_true(_anim.autoplay.is_empty(), "AnimationPlayer 不得设置 autoplay")
	assert_true(_mesh.rotation.is_equal_approx(CLOSE_ROTATION), "初始旋转应为关闭姿态")
