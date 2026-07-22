// ============================================================================
//  CardAutoReply 设置界面（AHRCardAutoReplyEditor） — iOS 26 液态玻璃风
//  由聊天「+」面板里的入口项呼出（见 PanelIntegration.xm，走 +present）
// ============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// —— 与 Tweak.xm 共享的存储 ——
static NSString * const kAHRDefaults    = @"AHRCardAutoReply.rules";
static NSString * const kAHREnabled     = @"AHRCardAutoReply.enabled";
static NSString * const kAHRCooldownMin = @"AHRCardAutoReply.cooldownMin";
static NSString * const kR_keyword = @"keyword";
static NSString * const kR_cover   = @"cover";
static NSString * const kR_title   = @"title";
static NSString * const kR_desc    = @"desc";
static NSString * const kR_link    = @"link";
static NSString * const kR_exact   = @"exact";   // 1=精准 0=模糊

@interface AHRStore : NSObject
+ (BOOL)enabled; + (void)setEnabled:(BOOL)e;
+ (NSInteger)cooldownMinutes; + (void)setCooldownMinutes:(NSInteger)m;
+ (NSMutableArray *)rules; + (void)saveRules:(NSArray *)rules;
@end

#pragma mark - 视觉工具

static UIColor *AHRAccent(void) {           // 主题渐变的代表色
    return [UIColor colorWithRed:0.98 green:0.22 blue:0.42 alpha:1.0];
}
static UIColor *AHRAccent2(void) {
    return [UIColor colorWithRed:0.60 green:0.18 blue:0.92 alpha:1.0];
}

// 液态玻璃背景（iOS 26 UIGlassEffect；老系统降级为 UIBlurEffect）
static UIVisualEffectView *AHRGlassView(void) {
    UIVisualEffect *fx = nil;
    Class glass = objc_getClass("UIGlassEffect");
    if (glass) {
        @try { fx = [[glass alloc] init]; } @catch (__unused NSException *e) {}
    }
    if (!fx) fx = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    UIVisualEffectView *v = [[UIVisualEffectView alloc] initWithEffect:fx];
    v.layer.cornerRadius = 22;
    v.layer.cornerCurve  = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
    return v;
}

static void AHRRoundContinuous(UIView *v, CGFloat r) {
    v.layer.cornerRadius = r;
    v.layer.cornerCurve  = kCACornerCurveContinuous;
    v.clipsToBounds = YES;
}

// SF Symbol（带回退）
static UIImage *AHRSymbol(NSString *name, CGFloat size) {
    if (![UIImage respondsToSelector:@selector(systemImageNamed:)]) return nil;
    UIImage *img = [UIImage systemImageNamed:name];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold];
        img = [img imageByApplyingSymbolConfiguration:cfg] ?: img;
    }
    return img;
}

#pragma mark - 单条卡片规则编辑页（带实时预览）

@interface AHRRuleEditViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) NSMutableDictionary *rule;
@property (nonatomic, copy)   void (^onSave)(NSMutableDictionary *rule);
@property (nonatomic, copy)   void (^onDelete)(void);
@property (nonatomic, strong) NSMutableDictionary<NSString *, UITextField *> *fields;
@property (nonatomic, strong) UILabel *pvTitle, *pvDesc, *pvHost;
@property (nonatomic, strong) UIImageView *pvCover;
@property (nonatomic, strong) UISegmentedControl *matchSeg;
@property (nonatomic, strong) UIScrollView *scroll;
@property (nonatomic, weak)   UITextField *activeField;
@end

@implementation AHRRuleEditViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"编辑卡片";
    self.fields = [NSMutableDictionary dictionary];
    if (@available(iOS 13.0, *)) self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    else self.view.backgroundColor = [UIColor whiteColor];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
            target:self action:@selector(save)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
            target:self action:@selector(cancel)];

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.scroll = scroll;
    [self.view addSubview:scroll];

    // 键盘避让
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbWillChange:)
        name:UIKeyboardWillChangeFrameNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(kbWillHide:)
        name:UIKeyboardWillHideNotification object:nil];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:scroll.topAnchor constant:20],
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:-24],
    ]];

    [stack addArrangedSubview:[self buildPreviewCard]];

    // 字段
    [stack addArrangedSubview:[self fieldRowKey:kR_keyword icon:@"number" title:@"关键词" placeholder:@"多个词用，、,分隔｜留空=默认" keyboard:UIKeyboardTypeDefault]];
    [stack addArrangedSubview:[self matchModeRow]];
    [stack addArrangedSubview:[self fieldRowKey:kR_title   icon:@"textformat" title:@"标题" placeholder:@"卡片标题" keyboard:UIKeyboardTypeDefault]];
    [stack addArrangedSubview:[self fieldRowKey:kR_desc    icon:@"text.alignleft" title:@"描述" placeholder:@"卡片描述" keyboard:UIKeyboardTypeDefault]];
    [stack addArrangedSubview:[self fieldRowKey:kR_cover   icon:@"photo" title:@"封面 URL" placeholder:@"https://…" keyboard:UIKeyboardTypeURL]];
    [stack addArrangedSubview:[self fieldRowKey:kR_link    icon:@"link" title:@"跳转链接" placeholder:@"https://…" keyboard:UIKeyboardTypeURL]];

    if (self.onDelete) {
        UIButton *del = [UIButton buttonWithType:UIButtonTypeSystem];
        [del setTitle:@"删除此规则" forState:UIControlStateNormal];
        [del setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
        del.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [del addTarget:self action:@selector(deleteRule) forControlEvents:UIControlEventTouchUpInside];
        [stack addArrangedSubview:del];
    }
    [self refreshPreview];
}

- (UIView *)buildPreviewCard {
    // 外层玻璃卡
    UIVisualEffectView *glass = AHRGlassView();
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [glass.heightAnchor constraintEqualToConstant:96].active = YES;

    // 渐变描边感：底色叠一层
    UIView *content = glass.contentView;

    self.pvCover = [[UIImageView alloc] init];
    self.pvCover.translatesAutoresizingMaskIntoConstraints = NO;
    self.pvCover.contentMode = UIViewContentModeScaleAspectFill;
    self.pvCover.backgroundColor = [UIColor colorWithWhite:0.5 alpha:0.18];
    self.pvCover.image = AHRSymbol(@"photo", 22);
    self.pvCover.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    AHRRoundContinuous(self.pvCover, 14);
    [content addSubview:self.pvCover];

    self.pvTitle = [[UILabel alloc] init];
    self.pvTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.pvTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    self.pvTitle.textColor = [UIColor labelColor];
    self.pvTitle.numberOfLines = 1;

    self.pvDesc = [[UILabel alloc] init];
    self.pvDesc.translatesAutoresizingMaskIntoConstraints = NO;
    self.pvDesc.font = [UIFont systemFontOfSize:13];
    self.pvDesc.textColor = [UIColor secondaryLabelColor];
    self.pvDesc.numberOfLines = 2;

    self.pvHost = [[UILabel alloc] init];
    self.pvHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.pvHost.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.pvHost.textColor = [UIColor tertiaryLabelColor];

    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[self.pvTitle, self.pvDesc, self.pvHost]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 3;
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:texts];

    [NSLayoutConstraint activateConstraints:@[
        [self.pvCover.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:14],
        [self.pvCover.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [self.pvCover.widthAnchor constraintEqualToConstant:64],
        [self.pvCover.heightAnchor constraintEqualToConstant:64],
        [texts.leadingAnchor constraintEqualToAnchor:self.pvCover.trailingAnchor constant:14],
        [texts.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-14],
        [texts.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
    ]];
    return glass;
}

// 单个输入行：图标 + 标题 + 输入框，整体一张圆角玻璃
- (UIView *)fieldRowKey:(NSString *)key icon:(NSString *)icon title:(NSString *)title
            placeholder:(NSString *)ph keyboard:(UIKeyboardType)kb {
    UIView *card = [[UIView alloc] init];
    if (@available(iOS 13.0, *)) card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    else card.backgroundColor = [UIColor whiteColor];
    AHRRoundContinuous(card, 16);
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iconV = [[UIImageView alloc] initWithImage:AHRSymbol(icon, 15)];
    iconV.translatesAutoresizingMaskIntoConstraints = NO;
    iconV.tintColor = AHRAccent();
    iconV.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *lab = [[UILabel alloc] init];
    lab.text = title;
    lab.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    lab.textColor = [UIColor secondaryLabelColor];
    lab.translatesAutoresizingMaskIntoConstraints = NO;

    UITextField *tf = [[UITextField alloc] init];
    tf.placeholder = ph;
    tf.text = self.rule[key] ?: @"";
    tf.font = [UIFont systemFontOfSize:16];
    tf.textColor = [UIColor labelColor];
    tf.keyboardType = kb;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.delegate = self;
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    [tf addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    self.fields[key] = tf;

    UIStackView *right = [[UIStackView alloc] initWithArrangedSubviews:@[lab, tf]];
    right.axis = UILayoutConstraintAxisVertical;
    right.spacing = 2;
    right.translatesAutoresizingMaskIntoConstraints = NO;

    [card addSubview:iconV];
    [card addSubview:right];
    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintGreaterThanOrEqualToConstant:62],
        [iconV.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [iconV.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconV.widthAnchor constraintEqualToConstant:22],
        [iconV.heightAnchor constraintEqualToConstant:22],
        [right.leadingAnchor constraintEqualToAnchor:iconV.trailingAnchor constant:12],
        [right.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [right.topAnchor constraintEqualToAnchor:card.topAnchor constant:10],
        [right.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-10],
    ]];
    return card;
}

- (UIView *)matchModeRow {
    UIView *card = [[UIView alloc] init];
    if (@available(iOS 13.0, *)) card.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    else card.backgroundColor = [UIColor whiteColor];
    AHRRoundContinuous(card, 16);
    card.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *iconV = [[UIImageView alloc] initWithImage:AHRSymbol(@"scope", 15)];
    iconV.translatesAutoresizingMaskIntoConstraints = NO;
    iconV.tintColor = AHRAccent();

    UILabel *lab = [[UILabel alloc] init];
    lab.text = @"匹配方式";
    lab.font = [UIFont systemFontOfSize:15];
    lab.textColor = [UIColor labelColor];
    lab.translatesAutoresizingMaskIntoConstraints = NO;
    [lab setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];

    self.matchSeg = [[UISegmentedControl alloc] initWithItems:@[@"模糊", @"精准"]];
    self.matchSeg.selectedSegmentIndex = [self.rule[kR_exact] boolValue] ? 1 : 0;
    self.matchSeg.selectedSegmentTintColor = AHRAccent();
    self.matchSeg.translatesAutoresizingMaskIntoConstraints = NO;
    [self.matchSeg setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];

    [card addSubview:iconV];
    [card addSubview:lab];
    [card addSubview:self.matchSeg];
    [NSLayoutConstraint activateConstraints:@[
        [card.heightAnchor constraintEqualToConstant:58],
        [iconV.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [iconV.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [iconV.widthAnchor constraintEqualToConstant:22],
        [iconV.heightAnchor constraintEqualToConstant:22],
        [lab.leadingAnchor constraintEqualToAnchor:iconV.trailingAnchor constant:12],
        [lab.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [self.matchSeg.leadingAnchor constraintGreaterThanOrEqualToAnchor:lab.trailingAnchor constant:12],
        [self.matchSeg.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [self.matchSeg.centerYAnchor constraintEqualToAnchor:card.centerYAnchor],
        [self.matchSeg.widthAnchor constraintEqualToConstant:140],
    ]];
    return card;
}

- (void)fieldChanged:(UITextField *)tf { [self refreshPreview]; }

- (NSString *)hostFromURL:(NSString *)s {
    NSURL *u = [NSURL URLWithString:s ?: @""];
    return u.host ?: (s.length ? s : @"未设置链接");
}

- (void)refreshPreview {
    NSString *t = self.fields[kR_title].text;
    NSString *d = self.fields[kR_desc].text;
    NSString *l = self.fields[kR_link].text;
    self.pvTitle.text = t.length ? t : @"卡片标题";
    self.pvDesc.text  = d.length ? d : @"卡片描述会显示在这里";
    self.pvHost.text  = [@"🔗 " stringByAppendingString:[self hostFromURL:l]];
}

- (void)save {
    for (NSString *k in self.fields) self.rule[k] = self.fields[k].text ?: @"";
    self.rule[kR_exact] = @(self.matchSeg.selectedSegmentIndex == 1);
    if (self.onSave) self.onSave(self.rule);
    [self.navigationController popViewControllerAnimated:YES];
}
- (void)cancel { [self.navigationController popViewControllerAnimated:YES]; }
- (void)deleteRule {
    if (self.onDelete) self.onDelete();
    [self.navigationController popViewControllerAnimated:YES];
}
- (BOOL)textFieldShouldReturn:(UITextField *)tf { [tf resignFirstResponder]; return YES; }
- (void)textFieldDidBeginEditing:(UITextField *)tf {
    self.activeField = tf;
    dispatch_async(dispatch_get_main_queue(), ^{ [self scrollActiveFieldVisible]; });
}

#pragma mark 键盘避让

- (void)kbWillChange:(NSNotification *)n {
    CGRect endF = [n.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect endInView = [self.view convertRect:endF fromView:nil];
    CGFloat overlap = CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(endInView);
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat bottom = MAX(0, overlap - safeBottom);

    UIEdgeInsets ins = self.scroll.contentInset;
    ins.bottom = bottom;
    self.scroll.contentInset = ins;
    UIEdgeInsets si = self.scroll.verticalScrollIndicatorInsets;
    si.bottom = bottom;
    self.scroll.verticalScrollIndicatorInsets = si;

    [self scrollActiveFieldVisible];
}

- (void)kbWillHide:(NSNotification *)n {
    UIEdgeInsets ins = self.scroll.contentInset; ins.bottom = 0; self.scroll.contentInset = ins;
    UIEdgeInsets si = self.scroll.verticalScrollIndicatorInsets; si.bottom = 0;
    self.scroll.verticalScrollIndicatorInsets = si;
}

- (void)scrollActiveFieldVisible {
    if (!self.activeField || !self.activeField.window) return;
    // 用输入框所在的整张卡片，留出余量
    UIView *card = self.activeField.superview ?: self.activeField;
    while (card.superview && card.superview != self.scroll) card = card.superview;
    CGRect r = [card convertRect:card.bounds toView:self.scroll];
    [self.scroll scrollRectToVisible:CGRectInset(r, 0, -16) animated:YES];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

@end

#pragma mark - 规则列表主页

@interface AHRCardAutoReplyEditor : UITableViewController
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *rules;
+ (void)present;
@end

static UIViewController *AHRTopVC(void);

@implementation AHRCardAutoReplyEditor

- (instancetype)init {
    if (@available(iOS 13.0, *)) return [super initWithStyle:UITableViewStyleInsetGrouped];
    return [super initWithStyle:UITableViewStyleGrouped];
}

+ (void)present {
    UIViewController *top = AHRTopVC();
    if (!top) return;
    UIViewController *check = top;
    if ([check isKindOfClass:[UINavigationController class]])
        check = [(UINavigationController *)check topViewController];
    if ([check isKindOfClass:[AHRCardAutoReplyEditor class]]) return;

    AHRCardAutoReplyEditor *editor = [[AHRCardAutoReplyEditor alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:editor];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    if (@available(iOS 13.0, *)) nav.navigationBar.prefersLargeTitles = YES;
    [top presentViewController:nav animated:YES completion:nil];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"自动回复卡片";
    if (@available(iOS 11.0, *)) self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.rules = [AHRStore rules];

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithTitle:@"完成"
        style:UIBarButtonItemStyleDone target:self action:@selector(dismissSelf)];
    done.tintColor = AHRAccent();
    self.navigationItem.leftBarButtonItem = done;
    UIBarButtonItem *add = [[UIBarButtonItem alloc]
        initWithImage:AHRSymbol(@"plus.circle.fill", 20) style:UIBarButtonItemStylePlain
        target:self action:@selector(addRule)];
    add.tintColor = AHRAccent();
    self.navigationItem.rightBarButtonItem = add;

    [self setupHeader];
}

- (void)setupHeader {
    CGFloat W = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 150)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIVisualEffectView *glass = AHRGlassView();
    glass.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:glass];
    UIView *cv = glass.contentView;

    // 渐变图标徽章（固定 60x60，渐变用固定 bounds）
    UIView *badge = [[UIView alloc] init];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    AHRRoundContinuous(badge, 18);
    CAGradientLayer *g = [CAGradientLayer layer];
    g.frame = CGRectMake(0, 0, 60, 60);
    g.colors = @[(id)AHRAccent().CGColor, (id)AHRAccent2().CGColor];
    g.startPoint = CGPointMake(0,0); g.endPoint = CGPointMake(1,1);
    g.cornerRadius = 18; g.cornerCurve = kCACornerCurveContinuous;
    [badge.layer insertSublayer:g atIndex:0];
    UIImageView *bi = [[UIImageView alloc] initWithImage:AHRSymbol(@"bubble.left.and.text.bubble.right.fill", 25)];
    bi.translatesAutoresizingMaskIntoConstraints = NO;
    bi.tintColor = [UIColor whiteColor];
    [badge addSubview:bi];
    [cv addSubview:badge];

    UILabel *t = [[UILabel alloc] init];
    t.text = @"收到私信 · 自动回卡片";
    t.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    t.textColor = [UIColor labelColor];
    t.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *s = [[UILabel alloc] init];
    s.text = @"关键词可填多个（，、, 分隔），命中任一即回；未命中发默认卡片；每会话按冷却限频。";
    s.font = [UIFont systemFontOfSize:12.5];
    s.textColor = [UIColor secondaryLabelColor];
    s.numberOfLines = 0;
    s.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *texts = [[UIStackView alloc] initWithArrangedSubviews:@[t, s]];
    texts.axis = UILayoutConstraintAxisVertical;
    texts.spacing = 5;
    texts.alignment = UIStackViewAlignmentLeading;
    texts.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:texts];

    [NSLayoutConstraint activateConstraints:@[
        [glass.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],
        [glass.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:18],
        [glass.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-18],
        [glass.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-14],

        [badge.leadingAnchor constraintEqualToAnchor:cv.leadingAnchor constant:16],
        [badge.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
        [badge.widthAnchor constraintEqualToConstant:60],
        [badge.heightAnchor constraintEqualToConstant:60],
        [bi.centerXAnchor constraintEqualToAnchor:badge.centerXAnchor],
        [bi.centerYAnchor constraintEqualToAnchor:badge.centerYAnchor],

        [texts.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:14],
        [texts.trailingAnchor constraintEqualToAnchor:cv.trailingAnchor constant:-16],
        [texts.centerYAnchor constraintEqualToAnchor:cv.centerYAnchor],
    ]];

    self.tableView.tableHeaderView = header;
}

- (void)dismissSelf { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)persist { [AHRStore saveRules:self.rules]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)t { return 2; }
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return s == 0 ? 2 : self.rules.count + 1;   // 规则区末尾加「添加规则」
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    return s == 0 ? @"总开关" : @"卡片规则";
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    return s == 1 ? @"关键词留空的规则作为默认卡片。左滑可删除。" : nil;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 0) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        c.selectionStyle = UITableViewCellSelectionStyleNone;
        if (ip.row == 0) {
            c.imageView.image = AHRSymbol(@"power.circle.fill", 22);
            c.imageView.tintColor = AHRAccent();
            c.textLabel.text = @"启用自动回复卡片";
            UISwitch *sw = [[UISwitch alloc] init];
            sw.onTintColor = AHRAccent();
            sw.on = [AHRStore enabled];
            [sw addTarget:self action:@selector(toggleEnabled:) forControlEvents:UIControlEventValueChanged];
            c.accessoryView = sw;
        } else {
            c.imageView.image = AHRSymbol(@"timer", 22);
            c.imageView.tintColor = AHRAccent();
            c.textLabel.text = @"每会话冷却";
            c.detailTextLabel.text = [NSString stringWithFormat:@"%ld 分钟", (long)[AHRStore cooldownMinutes]];
            c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            c.selectionStyle = UITableViewCellSelectionStyleDefault;
            c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return c;
    }

    // 添加规则行
    if (ip.row == (NSInteger)self.rules.count) {
        UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        c.imageView.image = AHRSymbol(@"plus.circle.fill", 22);
        c.imageView.tintColor = AHRAccent();
        c.textLabel.text = @"添加规则";
        c.textLabel.textColor = AHRAccent();
        c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        return c;
    }

    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *r = self.rules[ip.row];
    BOOL isDefault = ![r[kR_keyword] length];
    c.imageView.image = AHRSymbol(isDefault ? @"star.circle.fill" : @"number.circle.fill", 24);
    c.imageView.tintColor = isDefault ? [UIColor systemOrangeColor] : AHRAccent();
    c.textLabel.text = isDefault ? @"默认卡片" : r[kR_keyword];
    c.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    NSString *title = [r[kR_title] length] ? r[kR_title] : @"（未设标题）";
    c.detailTextLabel.text = title;
    c.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [t deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 && ip.row == 1) { [self editCooldown]; return; }
    if (ip.section == 1) {
        if (ip.row == (NSInteger)self.rules.count) [self addRule];
        else [self editRuleAtIndex:ip.row];
    }
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == 1 && ip.row < (NSInteger)self.rules.count;
}
- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)style
                                 forRowAtIndexPath:(NSIndexPath *)ip {
    if (style == UITableViewCellEditingStyleDelete) {
        [self.rules removeObjectAtIndex:ip.row];
        [self persist];
        [t deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

#pragma mark 交互

- (void)toggleEnabled:(UISwitch *)sw { [AHRStore setEnabled:sw.on]; }

- (void)editCooldown {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"每会话冷却"
        message:@"两次自动回复的最小间隔（分钟），0 表示不限制" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeNumberPad;
        tf.text = [NSString stringWithFormat:@"%ld", (long)[AHRStore cooldownMinutes]];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault
        handler:^(UIAlertAction *x) {
            [AHRStore setCooldownMinutes:[a.textFields.firstObject.text integerValue]];
            [self.tableView reloadData];
        }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)addRule {
    NSMutableDictionary *r = [@{ kR_keyword:@"", kR_cover:@"", kR_title:@"", kR_desc:@"", kR_link:@"" } mutableCopy];
    __weak typeof(self) ws = self;
    AHRRuleEditViewController *vc = [AHRRuleEditViewController new];
    vc.rule = r;
    vc.onSave = ^(NSMutableDictionary *saved) {
        [ws.rules addObject:saved]; [ws persist]; [ws.tableView reloadData];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)editRuleAtIndex:(NSInteger)idx {
    if (idx < 0 || idx >= (NSInteger)self.rules.count) return;
    __weak typeof(self) ws = self;
    AHRRuleEditViewController *vc = [AHRRuleEditViewController new];
    vc.rule = [self.rules[idx] mutableCopy];
    vc.onSave = ^(NSMutableDictionary *saved) {
        if (idx < (NSInteger)ws.rules.count) ws.rules[idx] = saved;
        [ws persist]; [ws.tableView reloadData];
    };
    vc.onDelete = ^{
        if (idx < (NSInteger)ws.rules.count) [ws.rules removeObjectAtIndex:idx];
        [ws persist]; [ws.tableView reloadData];
    };
    [self.navigationController pushViewController:vc animated:YES];
}

@end

#pragma mark - 取顶层 VC（供 +present 用）

static UIViewController *AHRTopVC(void) {
    UIWindow *w = nil;
    for (UIWindow *win in UIApplication.sharedApplication.windows) {
        if (win.isKeyWindow) { w = win; break; }
    }
    if (!w) w = UIApplication.sharedApplication.keyWindow;
    UIViewController *vc = w.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}
