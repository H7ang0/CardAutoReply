// ============================================================================
//  CardAutoReply  —  抖音私信「自动回复卡片」模块
//  ---------------------------------------------------------------------------
//  设计：
//    * 收到对方私信 -> 关键词匹配 -> 命中则回一张卡片；未命中走「默认卡片」
//    * 卡片内容可配多条规则（关键词 / 封面URL / 标题 / 描述 / 跳转链接）
//    * 每个会话冷却 N 分钟，避免刷屏 / 触发风控
//    * 卡片发送全部走抖音原生类，零第三方 dylib 依赖
//
//  接线点（来自 Aweme class-dump）：
//    - 收私信 : TIMXOThirdPartyConversationNotifier -didInsertNewMessages:belongingConversation:
//               （TIMX SDK 全局单例，所有会话共用；不依赖聊天页打开）
//               每条 TIMXOMessage: belongingConversationIdentifier(会话ID) / content(内容字典) /
//               sender(发送者uid) / messageType。自己发的用 sender==currentUserID 过滤。
//    - 发卡片 : 逆向 DouyinHelper 二进制得到的确切配方——
//                IESIMSendMessageModel(initWithConversationId:, messageType=26,
//                messageContentDict={cover_url,title,desc,link_url}) 经 IESIMMessageSender
//                asyncSendMessage:completion: 发送。纯 IM SDK，零私有依赖。
//    - 判方向 : AWEIMMessage -sendFromMe（抖音官方，判断是不是自己发的）
// ============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#pragma mark - 抖音原生类（只声明，运行时链接；不依赖任何第三方 dylib）
// 发送逻辑逆向自 DouyinHelper 二进制的 _internalSendLinkCardToConversation:...
// 纯抖音 IM SDK 调用：IESIMSendMessageModel(type=26 链接卡片) + IESIMMessageSender

@interface IESIMSendMessageModel : NSObject
- (id)initWithConversationId:(id)a0;
@property (nonatomic) long long messageType;
@property (copy, nonatomic) NSDictionary *messageContentDict;
@end

@interface IESIMMessageSender : NSObject
// DouyinHelper 逆向确认：completion 只有一个参数
- (void)asyncSendMessage:(id)a0 completion:(void (^)(id result))a1;
- (id)sendMessage:(id)a0;
@end

@interface AWEIMUser : NSObject
@property (copy, nonatomic) NSString *uid;
@end

@interface AWEIMMessageConversation : NSObject
@property (copy, nonatomic) NSString *conversationID;
@property (nonatomic) id con;            // id<IESIMConversationProtocol>
@end

@interface AWEIMMessageListViewModel : NSObject
@property (retain, nonatomic) AWEIMMessageConversation *conversation;
@end

@interface AWEIMMessageListDataComponent : NSObject
@property (retain, nonatomic) AWEIMMessageListViewModel *listViewModel;
@end

#pragma mark - 配置存储

static NSString * const kAHRDefaults      = @"AHRCardAutoReply.rules";       // 规则数组
static NSString * const kAHREnabled       = @"AHRCardAutoReply.enabled";     // 总开关
static NSString * const kAHRCooldownMin   = @"AHRCardAutoReply.cooldownMin"; // 冷却分钟
static NSString * const kAHRLastSend      = @"AHRCardAutoReply.lastSend";    // 会话->时间戳

// 每条规则的字段
static NSString * const kR_keyword = @"keyword"; // 空 = 默认卡片(兜底)
static NSString * const kR_cover   = @"cover";
static NSString * const kR_title   = @"title";
static NSString * const kR_desc    = @"desc";
static NSString * const kR_link    = @"link";
static NSString * const kR_exact   = @"exact";   // 1=精准(整条消息等于关键词) 0=模糊(包含)

@interface AHRStore : NSObject
+ (BOOL)enabled;
+ (void)setEnabled:(BOOL)e;
+ (NSInteger)cooldownMinutes;                 // 默认 5
+ (void)setCooldownMinutes:(NSInteger)m;
+ (NSMutableArray<NSMutableDictionary *> *)rules;
+ (void)saveRules:(NSArray *)rules;
// 匹配：先按非空关键词命中(不区分大小写)，否则用默认卡片(空关键词)
+ (NSDictionary *)matchRuleForText:(NSString *)text;
// 冷却
+ (BOOL)canSendForConversation:(NSString *)convID;
+ (void)markSentForConversation:(NSString *)convID;
@end

@implementation AHRStore

+ (NSUserDefaults *)ud { return [NSUserDefaults standardUserDefaults]; }

+ (BOOL)enabled { return [[self ud] boolForKey:kAHREnabled]; }
+ (void)setEnabled:(BOOL)e { [[self ud] setBool:e forKey:kAHREnabled]; [[self ud] synchronize]; }

+ (NSInteger)cooldownMinutes {
    id v = [[self ud] objectForKey:kAHRCooldownMin];
    return v ? MAX(0, [v integerValue]) : 5;
}
+ (void)setCooldownMinutes:(NSInteger)m {
    [[self ud] setInteger:MAX(0, m) forKey:kAHRCooldownMin]; [[self ud] synchronize];
}

+ (NSMutableArray<NSMutableDictionary *> *)rules {
    NSArray *raw = [[self ud] arrayForKey:kAHRDefaults];
    NSMutableArray *out = [NSMutableArray array];
    for (id d in raw) {
        if ([d isKindOfClass:[NSDictionary class]]) [out addObject:[d mutableCopy]];
    }
    return out;
}
+ (void)saveRules:(NSArray *)rules {
    [[self ud] setObject:(rules ?: @[]) forKey:kAHRDefaults];
    [[self ud] synchronize];
}

// 把关键词框拆成多个词：支持中文逗号，、顿号、英文逗号,、分号；空格、竖线|、斜杠/ 分隔
+ (NSArray<NSString *> *)splitKeywords:(NSString *)kw {
    static NSCharacterSet *seps = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        seps = [NSCharacterSet characterSetWithCharactersInString:@"，,、;；| /\t\n\r"];
    });
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *piece in [kw componentsSeparatedByCharactersInSet:seps]) {
        NSString *w = [piece stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (w.length) [out addObject:w];
    }
    return out;
}

+ (NSDictionary *)matchRuleForText:(NSString *)text {
    NSString *t = text ?: @"";
    NSString *tt = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSDictionary *fallback = nil;
    for (NSDictionary *r in [self rules]) {
        NSString *kw = [r[kR_keyword] isKindOfClass:[NSString class]] ? r[kR_keyword] : @"";
        NSArray<NSString *> *words = [self splitKeywords:kw];
        if (words.count == 0) {
            if (!fallback) fallback = r;          // 记住第一条默认卡片（关键词全空）
            continue;
        }
        BOOL exact = [r[kR_exact] boolValue];
        BOOL hit = NO;
        for (NSString *w in words) {              // 命中任意一个关键词即算中
            if (exact) {
                // 精准：整条消息(去空白)等于某个关键词，不区分大小写
                hit = ([tt caseInsensitiveCompare:w] == NSOrderedSame);
            } else {
                // 模糊：消息包含某个关键词
                hit = ([t rangeOfString:w options:NSCaseInsensitiveSearch].location != NSNotFound);
            }
            if (hit) break;
        }
        if (hit) return r;                         // 关键词优先
    }
    return fallback;                               // 没命中关键词 -> 默认卡片(可能为 nil)
}

+ (BOOL)canSendForConversation:(NSString *)convID {
    if (convID.length == 0) return NO;
    NSInteger cd = [self cooldownMinutes];
    if (cd <= 0) return YES;
    NSDictionary *map = [[self ud] dictionaryForKey:kAHRLastSend];
    id last = map[convID];
    if (!last) return YES;
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSince1970] - [last doubleValue];
    return elapsed >= cd * 60.0;
}
+ (void)markSentForConversation:(NSString *)convID {
    if (convID.length == 0) return;
    NSMutableDictionary *map = [([[self ud] dictionaryForKey:kAHRLastSend] ?: @{}) mutableCopy];
    map[convID] = @([[NSDate date] timeIntervalSince1970]);
    [[self ud] setObject:map forKey:kAHRLastSend];
    [[self ud] synchronize];
}
@end

#pragma mark - TIMXO 全局消息解析

// 底层消息（抖音 IM SDK）
@interface TIMXOMessage : NSObject
@property (readonly) NSString *belongingConversationIdentifier;
@property (readonly) NSDictionary *content;
@property (readonly) long long messageType;
@property (readonly) long long sender;        // 发送者 uid
@property (readonly) NSString *senderSecID;
@end

// 从全局通知器（其 _r 是 TIMXSDKInstance）尽力取当前登录 uid。取不到返回 0。
static long long AHRCurrentUID(id notifier) {
    static long long cached = 0;
    static BOOL tried = NO;
    if (cached != 0) return cached;
    if (tried && cached == 0) { /* 允许再试，登录后可能才有 */ }
    @try {
        id r = nil;
        @try { r = [notifier valueForKey:@"_r"]; } @catch (__unused NSException *e) {}
        // 直接问 _r，或 _r.client / _r.imClient 的 currentUserID
        NSArray *targets = r ? @[r] : @[];
        for (id t in targets) {
            for (NSString *ck in @[ @"currentUserID" ]) {
                SEL s = NSSelectorFromString(ck);
                if ([t respondsToSelector:s]) {
                    long long v = ((long long(*)(id, SEL))objc_msgSend)(t, s);
                    if (v != 0) { cached = v; return cached; }
                }
            }
            for (NSString *ck in @[ @"client", @"imClient", @"IMClient" ]) {
                SEL s = NSSelectorFromString(ck);
                if ([t respondsToSelector:s]) {
                    id c = ((id(*)(id, SEL))objc_msgSend)(t, s);
                    if ([c respondsToSelector:@selector(currentUserID)]) {
                        long long v = ((long long(*)(id, SEL))objc_msgSend)(c, @selector(currentUserID));
                        if (v != 0) { cached = v; return cached; }
                    }
                }
            }
        }
    } @catch (__unused NSException *e) {}
    tried = YES;
    return cached;
}

// 从 TIMXOMessage.content 取纯文本（文本消息 content 通常是 {@"text":...}）。取不到返回 nil。
static NSString *AHRTIMXText(TIMXOMessage *msg) {
    NSString *result = nil;
    @try {
        NSDictionary *c = msg.content;
        if ([c isKindOfClass:[NSDictionary class]]) {
            id t = c[@"text"] ?: c[@"content"] ?: c[@"aweme_text"];
            if ([t isKindOfClass:[NSString class]]) result = t;
            // 兜底：扫描第一个较长的字符串值
            if (!result.length) {
                for (id v in c.allValues) {
                    if ([v isKindOfClass:[NSString class]] && [v length]) { result = v; break; }
                }
            }
        }
    } @catch (__unused NSException *e) {}
    result = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return result.length ? result : nil;
}

#pragma mark - 发送卡片

static void AHRSendCard(NSString *convId, NSDictionary *rule) {
    if (convId.length == 0 || !rule) return;

    Class ModelCls  = objc_getClass("IESIMSendMessageModel");
    Class SenderCls = objc_getClass("IESIMMessageSender");
    if (!ModelCls || !SenderCls) {
        NSLog(@"[CardAutoReply] 缺少 IESIMSendMessageModel/IESIMMessageSender，发送中止");
        return;
    }

    NSString *cover = rule[kR_cover] ?: @"";
    NSString *title = rule[kR_title] ?: @"";
    NSString *desc  = rule[kR_desc]  ?: @"";
    NSString *link  = rule[kR_link]  ?: @"";

    // DouyinHelper 在全局后台队列发送，这里对齐
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            // 一比一复刻 DouyinHelper._internalSendLinkCardToConversation:coverURL:title:desc:linkURL:
            IESIMSendMessageModel *model = [[ModelCls alloc] initWithConversationId:convId];
            model.messageType = 26;   // 链接/H5 卡片消息类型
            model.messageContentDict = @{
                @"cover_url": cover,
                @"title":     title,
                @"desc":      desc,
                @"link_url":  link,
            };

            IESIMMessageSender *sender = [[SenderCls alloc] init];
            NSLog(@"[CardAutoReply] 准备发卡片 conv=%@ type=26 content=%@", convId, model.messageContentDict);
            if ([sender respondsToSelector:@selector(asyncSendMessage:completion:)]) {
                // 单参数 completion（与 DouyinHelper 一致，避免读野指针崩溃）
                [sender asyncSendMessage:model completion:^(id result){
                    @try {
                        if ([result isKindOfClass:[NSError class]])
                            NSLog(@"[CardAutoReply] ❌ 发送失败: %@", result);
                        else
                            NSLog(@"[CardAutoReply] 回调 result=%@ (类:%@)", result, [result class]);
                    } @catch (__unused NSException *e) {}
                }];
            } else if ([sender respondsToSelector:@selector(sendMessage:)]) {
                [sender sendMessage:model];
                NSLog(@"[CardAutoReply] 已调用 sendMessage:(同步)");
            } else {
                NSLog(@"[CardAutoReply] IESIMMessageSender 无可用发送方法");
            }
        } @catch (NSException *e) {
            NSLog(@"[CardAutoReply] 发送异常: %@", e);
        }
    });
}

#pragma mark - 统一处理（匹配 + 冷却 + 发送）

static void AHRHandleIncoming(NSString *convId, NSString *text) {
    if (![AHRStore enabled]) return;
    if (convId.length == 0 || text.length == 0) return;

    NSDictionary *rule = [AHRStore matchRuleForText:text];
    if (!rule) return;                                       // 无命中且无默认卡片
    if (![AHRStore canSendForConversation:convId]) return;   // 冷却中

    [AHRStore markSentForConversation:convId];
    NSLog(@"[CardAutoReply] 命中 conv=%@ text=%@ -> 准备回卡片", convId, text);
    // 稍作延迟，更像真人 & 避开插入时序
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        AHRSendCard(convId, rule);
    });
}

#pragma mark - Hook: 全局收私信（不依赖聊天页打开）

%hook TIMXOThirdPartyConversationNotifier

// 每条新消息插入都会走这里（所有会话共用的单例）
- (void)didInsertNewMessages:(id)messages belongingConversation:(id)conv {
    %orig;
    @try {
        if (![messages isKindOfClass:[NSArray class]]) return;
        if (![AHRStore enabled]) return;

        long long myUid = AHRCurrentUID(self);   // 取不到返回 0

        for (TIMXOMessage *m in (NSArray *)messages) {
            @try {
                // 自己发的跳过（取不到 uid 时不拦，靠冷却兜底）
                if (myUid != 0 && m.sender == myUid) continue;

                NSString *text = AHRTIMXText(m);
                if (text.length == 0) continue;              // 非文本不触发

                NSString *convId = m.belongingConversationIdentifier;
                if (convId.length == 0 && [conv respondsToSelector:@selector(conversationID)])
                    convId = ((id(*)(id, SEL))objc_msgSend)(conv, @selector(conversationID));
                AHRHandleIncoming(convId, text);
            } @catch (__unused NSException *e) {}
        }
    } @catch (NSException *e) {
        NSLog(@"[CardAutoReply] 全局hook异常: %@", e);
    }
}

%end

// 设置入口在聊天「+」面板里，见 PanelIntegration.xm。
