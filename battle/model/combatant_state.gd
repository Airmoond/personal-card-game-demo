## 保存一名战斗角色的运行时状态。
##
## 该对象可以表示玩家或敌人，负责保存名称、生命和格挡等真实数据。
## 它不挂载到节点，也不负责角色画面、动画、回合流程或胜负判断。
class_name CombatantState
extends RefCounted

## 角色显示名称。
var combatant_name:String;

## 角色的最大生命值。
##
## 成功初始化后必须大于0。
var max_health:int = 0;

## 角色当前剩余的生命值。
##
## 初始化时等于max_health，受到伤害时减少，最低为0。
var current_health:int = 0;

## 角色当前拥有的格挡值。
##
## 格挡会优先抵消传入伤害，初始化时为0。
var current_block:int = 0;


## 使用角色名称和最大生命值初始化当前角色状态。
##
## max_hp小于或等于0时推送错误并立即结束，不修改当前数据。
## max_hp合法时，保存new_name和max_hp，将当前生命恢复至最大生命，并将格挡清零。
## 该方法没有返回值。
func combatant_init(new_name:String,max_hp:int)->void:
	if max_hp<=0:
		push_error("Invalid max_hp!非法的最大生命，初始化失败");#若生命值传入负数，则推送错误，中断初始化进程
		return;
	combatant_name=new_name;
	max_health = max_hp;
	current_health = max_health;
	current_block=0;


## 为角色增加指定数量的格挡。
##
## block_number大于0时，将其累加到current_block。
## block_number等于0时，格挡保持不变。
## block_number小于0时，不执行任何操作。
## 该方法没有返回值。
func gain_block(block_number:int)->void:
	if block_number>=0:
		current_block += block_number;


## 清空角色当前拥有的全部格挡。
##
## 调用后current_block变为0。
## 该方法不判断清空格挡的时机，也没有返回值。
func clear_block()->void:
	current_block = 0;


## 让角色承受指定数量的伤害，并返回实际损失的生命值。
##
## damage_number小于或等于0时，不修改生命和格挡，并返回0。
## damage_number大于0时，当前格挡会优先吸收伤害。
## 穿透格挡的剩余伤害会扣除当前生命，但不会让生命低于0。
## 伤害被格挡完全吸收时返回0。
## 伤害穿透格挡时返回本次实际减少的生命值。
## 发生超杀时只返回角色原本剩余的生命值。
func take_damage(damage_number:int)->int:
	var blocked_damage:int=0;#被格挡掉的伤害
	var remaining_damage:int=0;#穿透格挡的伤害
	var actual_hp_loss:int=0;#实际损失的hp值（防止超杀）
	if damage_number <= 0:#如果伤害小于等于0，什么都不做
		pass;
	else:
		blocked_damage=min(damage_number,current_block);#格挡掉的伤害=传入伤害和当前格挡的更小值
		current_block-=blocked_damage;#当前格挡值减去被格挡掉的伤害
		remaining_damage=damage_number-blocked_damage;#穿透伤害=传入伤害-被格挡的伤害
		actual_hp_loss=min(remaining_damage,current_health);#实际失去生命=穿透伤害和当前生命的更小值
		current_health-=actual_hp_loss;
	return actual_hp_loss;


## 判断角色当前是否存活。
##
## current_health大于0时返回true。
## current_health等于0或小于0时返回false。
## 该方法只进行判断，不修改角色状态。
func is_alive()->bool:
	if current_health>0:
		return true;
	else:
		return false;
