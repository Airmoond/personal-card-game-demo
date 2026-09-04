## 一种战斗角色的可复用静态定义资源。
##
## 保存角色不会随单场战斗变化的ID、显示名称、基础最大生命和原画。
## 玩家资源可以直接使用CombatantDefinition，后续EnemyDefinition也可以在它的基础上
## 增加敌人行动模式。多个运行时CombatantState可以共同引用同一份定义资源。
##
## 该资源在战斗过程中应当视为只读数据。当前生命、当前格挡和敌人当前行动等
## 临时变化必须保存在运行时状态中，不能写回CombatantDefinition。
class_name CombatantDefinition
extends Resource


## 程序内部使用的稳定唯一角色ID，例如player或cave_crawler。
##
## 该ID用于识别角色和查找配置，不应随着显示名称或语言变化而改变。
@export var combatant_id:String


## 显示给玩家的角色名称，例如“玩家”或“洞穴爬行者”。
##
## 该字段只负责静态显示信息，不作为程序内部识别角色的依据。
@export var display_name:String


## 角色原本拥有的最大生命值。
##
## 该数值必须大于0。运行时当前生命由CombatantState.current_health保存，
## 战斗中的伤害和恢复不能修改这里的基础最大生命。
@export var max_health:int = 0


## 角色界面使用的静态原画资源。
##
## CombatantView以后会通过运行时状态引用的定义读取该图片；
## 该字段只负责表现，不参与生命、格挡或行动规则计算。
@export var artwork:Texture2D


## 检查当前角色静态定义是否包含非法数据。
##
## combatant_id或display_name为空、max_health小于或等于0，或者artwork为空时，
## 推送对应错误并返回true。所有字段均满足第二阶段规则时返回false。
## 该方法只验证静态配置，不会修复资源，也不会创建或修改运行时角色状态。
func is_invalid()->bool:
	if combatant_id.is_empty():#程序内部必须拥有稳定且非空的角色ID
		push_error("Invalid combatant_id! 空角色ID");#报告无法识别角色的配置错误
		return true;#发现第一个错误后立即结束验证
	if display_name.is_empty():#角色界面必须拥有可以显示的名称
		push_error("Invalid display_name! 空角色显示名称");#报告缺少显示名称
		return true;#无效静态定义不能继续用于初始化
	if max_health <= 0:#最大生命必须能够创建一名存活角色
		push_error("Invalid max_health! 角色最大生命必须大于0");#报告非法的基础生命配置
		return true;#非正数生命无法生成合法运行时状态
	if artwork == null:#第二阶段要求角色原画由静态定义提供
		push_error("Invalid artwork! 角色原画为空");#报告缺失的表现资源
		return true;#缺少本阶段必需字段时判定定义无效
	return false;#所有静态字段均合法，当前角色定义可以使用
