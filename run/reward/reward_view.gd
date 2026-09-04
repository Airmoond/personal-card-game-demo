## 显示一组静态卡牌奖励选项，并报告玩家最终选择的奖励卡。
##
## GameFlowController以后从RunDefinition.reward_pool中无放回抽取候选卡牌，再通过
## setup传入本页面。RewardView为每个CardDefinition创建一个RewardCardView，
## 管理整组卡牌的交互状态，并把首次有效选择继续报告给流程控制器。
##
## RewardView属于视图与输入层。它不随机抽取奖励、不创建CardInstance，
## 不调用RunState.add_card，也不修改任何CardDefinition静态资源。
class_name RewardView
extends Control


## 每个奖励候选使用的可复用卡牌界面场景模板。
##
## refresh_options会为reward_options中的每个CardDefinition分别实例化一个组件。
const REWARD_CARD_VIEW_SCENE:PackedScene = preload(
	"res://run/reward/reward_card_view.tscn"
)


## 玩家首次选择当前页面中的一张有效奖励卡时发出。
##
## card_definition是被选择的只读静态卡牌定义。该信号只报告玩家意图，
## GameFlowController收到后仍需调用RunState.add_card执行真正的牌组成长。
signal reward_selected(card_definition:CardDefinition)


## 当前页面正在展示的全部静态奖励候选。
##
## setup会复制传入数组的结构；其中每个CardDefinition仍是原来的只读资源引用。
## 默认冒险传入三张不同卡牌，但页面本身不写死数量，以支持其他奖励规则复用。
var reward_options:Array[CardDefinition] = []


## 当前页面动态创建的全部RewardCardView组件。
##
## 数组只用于统一禁用和清理界面，不属于真实奖励数据，也不能代替reward_options。
var _reward_card_views:Array[RewardCardView] = []


## 当前这次setup之后是否已经向外报告过奖励选择。
##
## 单张RewardCardView会阻止自身重复点击；该页面级标记进一步阻止玩家快速点击
## 两张不同卡牌，导致同一次奖励流程发出多个reward_selected信号。
var _selection_reported:bool = false


## 动态RewardCardView组件的横向排列容器。
##
## 场景中必须存在center_container/main_layout/options_container路径。
@onready var options_container:HBoxContainer = (
	$center_container/main_layout/options_container
)


## 使用一组已经抽取完成的静态卡牌候选设置当前奖励页面。
##
## 数组为空、包含null、非法CardDefinition或重复card_id时，推送对应错误、
## 保持原有候选与界面不变并返回false。全部输入合法时复制数组结构、重置
## 页面级选择标记，再调用refresh_options创建完整界面。
##
## 创建失败时清理半成品组件和候选绑定并返回false；成功时返回true。
## 该方法应在页面进入场景树、@onready节点引用准备完成后调用。
func setup(new_options:Array[CardDefinition])->bool:
	if new_options.is_empty():#奖励页面至少需要一张可以展示和选择的候选卡
		push_error("奖励候选数组为空，奖励页面设置失败");#报告流程控制器没有传入实际奖励内容
		return false;#验证失败前保持当前页面原有候选和组件不变

	var validated_card_ids:Dictionary = {};#记录候选card_id，阻止同一次展示出现重复卡牌
	var validated_options:Array[CardDefinition] = [];#局部构建数组副本，全部验证通过后再提交
	for option_index in range(new_options.size()):#逐一验证流程控制器已经抽取出的全部候选
		var card_definition:CardDefinition = new_options[option_index];#取得当前位置的静态卡牌定义
		if card_definition == null:#空引用无法提供卡牌身份、费用、原画和描述
			push_error("奖励候选[%d]为空，奖励页面设置失败" % option_index);#报告空元素下标
			return false;#局部验证失败，不覆盖当前页面已有候选
		if card_definition.is_invalid():#卡牌ID、名称、费用、描述和效果必须完整合法
			push_error("奖励候选[%d]无效，奖励页面设置失败" % option_index);#补充数组位置上下文
			return false;#非法静态资源不能成为奖励卡界面的数据来源
		if validated_card_ids.has(card_definition.card_id):#同一次候选中不能出现相同稳定卡牌ID
			push_error("奖励候选中出现重复card_id：%s" % card_definition.card_id);#报告重复卡牌
			return false;#重复选项会削弱三选一并破坏无放回抽取约定

		validated_card_ids[card_definition.card_id] = true;#记录已经完整验证的候选身份
		validated_options.append(card_definition);#复制只读资源引用，不复制或修改资源本身

	reward_options = validated_options;#全部输入合法后一次性提交新的候选数组结构
	_selection_reported = false;#新的设置周期尚未向外报告过任何奖励选择

	if not refresh_options():#根据已经验证的候选创建并开放全部RewardCardView
		_clear_reward_card_views();#移除刷新过程中可能产生的半成品组件
		reward_options.clear();#清除未能成功显示的候选绑定，避免数据与画面不一致
		push_error("奖励卡界面刷新失败，奖励页面设置没有完成");#补充页面设置阶段上下文
		return false;#不把结构不完整的奖励页面交给流程控制器使用

	return true;#候选数据与全部奖励卡组件已经成功建立


## 根据reward_options完整重建当前页面中的奖励卡组件。
##
## 方法先防御性验证当前候选，再清理旧组件，为每张CardDefinition创建一个
## RewardCardView。任意实例化或设置失败时清理全部半成品并返回false。
## 该方法只重建显示，不重新抽卡，也不修改任何静态资源或RunState。
func refresh_options()->bool:
	if reward_options.is_empty():#缺少候选时无法创建任何有意义的奖励卡组件
		push_error("当前奖励候选为空，无法刷新奖励页面");#报告setup尚未成功完成或数据被损坏
		return false;#验证失败前保留当前页面已有的界面内容

	var configured_card_ids:Dictionary = {};#刷新前再次检查候选身份唯一性
	for option_index in range(reward_options.size()):#防御性验证当前绑定中的全部候选
		var card_definition:CardDefinition = reward_options[option_index];#取得当前候选定义
		if card_definition == null:#公开数组可能被外部错误写入空引用
			push_error("当前奖励候选[%d]为空，无法刷新奖励页面" % option_index);#报告损坏位置
			return false;#非法数据不能清空并覆盖当前界面
		if card_definition.is_invalid():#刷新时仍只允许完整合法的静态卡牌定义
			push_error("当前奖励候选[%d]无效，无法刷新奖励页面" % option_index);#补充位置上下文
			return false;#损坏候选不能生成可以点击的奖励卡
		if configured_card_ids.has(card_definition.card_id):#防止绑定后出现重复候选身份
			push_error("当前奖励候选中出现重复card_id：%s" % card_definition.card_id);#报告重复项
			return false;#重复候选不能覆盖当前已经存在的合法界面

		configured_card_ids[card_definition.card_id] = true;#记录已经验证的当前候选ID

	_clear_reward_card_views();#验证全部通过后再清理旧组件，避免非法数据清空现有页面

	for card_definition in reward_options:#按照候选数组顺序创建全部奖励卡组件
		var reward_card_view:RewardCardView = _create_reward_card_view(card_definition);#创建并设置一张卡
		if reward_card_view == null:#场景实例化、脚本类型或组件setup任一步骤失败
			_clear_reward_card_views();#移除当前刷新中已经创建的全部半成品卡牌
			return false;#结构不完整时不允许玩家进行奖励选择

		_reward_card_views.append(reward_card_view);#保存组件引用供统一禁用和后续清理

	return true;#全部候选都已拥有对应的可见RewardCardView


## 清理当前页面此前动态创建的全部RewardCardView组件。
##
## 只释放界面节点并清空临时组件数组，不删除reward_options中的静态卡牌候选。
func _clear_reward_card_views()->void:
	for reward_card_view in _reward_card_views:#逐一处理当前页面记录的奖励卡组件
		if not is_instance_valid(reward_card_view):#组件可能已经被其他页面清理流程提前释放
			continue;#无效对象不再执行场景树或释放操作
		if reward_card_view.get_parent() == options_container:#确认组件仍属于当前奖励容器
			options_container.remove_child(reward_card_view);#立即移出排版和输入系统
		reward_card_view.queue_free();#在当前帧安全结束后释放奖励卡组件

	_reward_card_views.clear();#删除只服务于当前界面的组件引用


## 为一张静态CardDefinition创建、设置并开放一个RewardCardView。
##
## 场景实例化或类型转换失败，或者组件setup失败时推送错误、清理当前实例并返回null。
## 成功时连接组件选择信号，根据页面是否已经选择设置交互权限，并返回组件引用。
func _create_reward_card_view(
	card_definition:CardDefinition
)->RewardCardView:
	if card_definition == null:#私有方法仍保留防御性检查，避免创建无法绑定的空卡牌
		push_error("需要创建界面的奖励卡牌定义为空");#报告调用顺序或候选数据损坏
		return null;#空定义不能产生有效RewardCardView

	var new_card_view:RewardCardView = (
		REWARD_CARD_VIEW_SCENE.instantiate() as RewardCardView
	);#由统一场景模板创建独立奖励卡组件
	if new_card_view == null:#场景根节点不是RewardCardView时类型转换会失败
		push_error("RewardCardView场景实例化失败");#报告场景根类型或脚本绑定不符合契约
		return null;#错误场景实例不能加入奖励页面

	new_card_view.name = "reward_card_%s" % card_definition.card_id;#使用稳定ID生成便于调试的节点名
	options_container.add_child(new_card_view);#先进入场景树，使组件内部@onready引用准备完成

	if not new_card_view.setup(card_definition):#绑定静态定义并刷新名称、费用、原画和描述
		options_container.remove_child(new_card_view);#设置失败时立即移出容器和输入系统
		new_card_view.queue_free();#安全释放无法使用的半成品组件
		return null;#当前候选创建失败，由refresh_options统一清理整组界面

	new_card_view.reward_card_selected.connect(
		_on_reward_card_selected
	);#单张卡牌选择先回到页面进行跨选项的一次性保护
	new_card_view.set_interactable(not _selection_reported);#页面尚未选择时才开放当前卡牌

	return new_card_view;#组件已经完成绑定、信号连接和交互状态设置


## 接收一张RewardCardView报告的玩家选择，并执行页面级最终验证。
##
## 页面已经报告过选择、参数为空、卡牌非法或不属于当前候选时忽略或推送错误。
## 首次合法选择会先记录页面级防重复状态，禁用全部奖励卡，再发出reward_selected。
## 该方法不调用RunState.add_card，真正的牌组修改仍由GameFlowController负责。
func _on_reward_card_selected(card_definition:CardDefinition)->void:
	if _selection_reported:#页面替换完成前可能快速点击两张不同的奖励卡
		return;#同一次setup周期最多向外报告一个最终选择
	if card_definition == null:#空参数无法对应当前候选中的实际卡牌
		push_error("奖励卡组件报告了空CardDefinition");#报告子组件信号数据损坏
		return;#不能向流程控制器转发空奖励
	if card_definition.is_invalid():#防止绑定后静态资源被意外修改为非法状态
		push_error("奖励卡组件报告了无效CardDefinition");#补充页面级选择验证上下文
		return;#非法卡牌不能加入本局牌组
	if not reward_options.has(card_definition):#只能选择当前页面实际展示的资源引用
		push_error("玩家选择的卡牌不属于当前奖励候选：%s" % card_definition.card_id);#报告越界选择
		return;#非候选卡牌不能进入流程层

	_selection_reported = true;#先提交页面级防重复状态，阻止其他卡牌的连续输入
	for reward_card_view in _reward_card_views:#统一禁用当前页面创建的全部奖励卡组件
		if is_instance_valid(reward_card_view):#忽略已经被外部页面清理流程释放的组件
			reward_card_view.set_interactable(false);#等待GameFlowController处理并替换奖励页面

	reward_selected.emit(card_definition);#只报告只读定义，由流程控制器调用RunState.add_card
