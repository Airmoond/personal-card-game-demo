## 按照加入顺序执行战斗行为。
##
## ActionQueue负责安排伤害、格挡和抽牌等操作的执行顺序。
## 第一阶段使用同步结算：加入行为后，由控制器立即调用resolve_all完成全部行为。
## 该对象不进入场景树，也不负责检查回合、卡牌费用、胜负或刷新界面。
class_name ActionQueue
extends RefCounted


## 等待执行的战斗行为。
##
## 每个Callable都保存了需要调用的方法以及调用时使用的参数。
var _pending_actions:Array[Callable] = [];


## 当前是否正在执行队列，防止重复调用resolve_all。
var _is_resolving:bool = false;

## 将一次伤害行为加入队列。
##
## target为空或damage_amount小于等于0时返回false。
## 成功时只加入队列，不会立刻造成伤害。
func queue_damage(target:CombatantState,damage_amount:int)->bool:
	if target == null:
		push_error("伤害目标为空，无法加入伤害行为");
		return false;
	if damage_amount <= 0:
		push_error("伤害数值必须大于0");
		return false;
	
	return _enqueue_action(target.take_damage.bind(damage_amount));
	

## 将一次获得格挡行为加入队列。
##
## target为空或block_amount小于等于0时返回false。
## 成功时只加入队列，不会立刻增加格挡。
func queue_block(target:CombatantState,block_amount:int)->bool:
	if target == null:
		push_error("格挡目标为空，无法加入格挡行为");
		return false;
	if block_amount <= 0:
		push_error("格挡数值必须大于0");
		return false;
	
	return _enqueue_action(target.gain_block.bind(block_amount));
	
## 将一次抽牌行为加入队列。
##
## state为空或draw_count小于等于0时返回false。
## 成功时只加入队列，不会立刻移动牌堆。
func queue_draw(state:BattleState,draw_count:int)->bool:
	if state == null:
		push_error("战斗状态为空，无法加入抽牌行为");
		return false;
	if draw_count <= 0:
		push_error("抽牌数量必须大于0");
		return false;
	
	return _enqueue_action(state.draw_multiple_cards.bind(draw_count));
	
## 验证并保存一个等待执行的行为。
func _enqueue_action(action:Callable)->bool:
	if not action.is_valid():
		push_error("尝试加入无效的战斗行为");
		return false;
	
	_pending_actions.push_back(action);
	return true;


## 按照加入顺序执行所有等待中的战斗行为。
##
## 队列为空时也返回true。
## 正在执行时再次调用该方法会返回false。
func resolve_all()->bool:
	if _is_resolving:
		push_error("行为队列正在执行，不能重复开始结算");
		return false;
	
	_is_resolving = true;
	
	while not _pending_actions.is_empty():
		var current_action:Callable = _pending_actions.pop_front();
		
		if not current_action.is_valid():
			push_error("行为队列中存在无效行为");
			_pending_actions.clear();
			_is_resolving = false;
			return false;
		
		current_action.call();
	
	_is_resolving = false;
	return true;
	
## 清除所有尚未执行的行为。
##
## 重新开始战斗或放弃当前结算时可以调用。
func clear_actions()->void:
	_pending_actions.clear();
