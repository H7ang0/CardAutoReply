// ============================================================================
//  CardAutoReply 入口集成 —— 聊天「+」面板 AWEIMPlusPanelView 九宫格加一项
//
//  面板数据源是 chatPanelModelArray(元素 AWEIMChatPanelModel)，可由三个方法重建：
//  reloadData / reloadDataWithPlatformChatPanelModels / updateDataSource:。
//  这里全部覆盖，并在 layoutSubviews 兜底，确保任何重建后都把我们的项追加回去。
//  带 [CardAutoReply] 前缀日志便于真机定位（Console.app 或 idevicesyslog 过滤该词）。
// ============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface AHRCardAutoReplyEditor : UITableViewController
+ (void)present;
@end

static NSString * const kAHRPanelItemLabel = @"自动回复卡片";
// 面板图标（自托管 https，light/dark 同一张；参考 DouyinHelper 的做法：设到基础模型 iconUrl）
static NSString * const kAHRIconURL = @"https://cayeye.uno/cared.png";

// 平台面板项模型（现代「+」面板整格靠它渲染：标题 + 图标URL）
@interface AWEIMPlatformChatPanelModel : NSObject
@property (nonatomic) unsigned long long chatPanelType;
@property (copy, nonatomic) NSString *panelTitle;
@property (copy, nonatomic) NSString *panelIconUrlLight;
@property (copy, nonatomic) NSString *panelIconUrlDark;
@property (nonatomic) unsigned long long showStatus;
@property (nonatomic) unsigned long long actionType;
@property (copy, nonatomic) NSString *action;
@property (nonatomic) BOOL needCheckAvailable;
@end

@interface AWEIMChatPanelModel : NSObject
@property (copy, nonatomic) NSString *labelText;
@property (retain, nonatomic) UIImage *buttonImage;
@property (nonatomic) BOOL isUnavailable;
@property (nonatomic) unsigned long long platformModelType;
@property (nonatomic) unsigned long long modelType;
@property (retain, nonatomic) AWEIMPlatformChatPanelModel *platformChatPanelModel;
@property (copy, nonatomic) id didSelectedAction;
// 关键：图标 URL 设在基础模型上（参考 DouyinHelper 逆向所得，light/dark 分别）
@property (copy, nonatomic) NSString *iconUrlLight;
@property (copy, nonatomic) NSString *iconUrlDark;
- (id)initWithDefault;
@end

@interface AWEIMPlusPanelView : UIView
@property (retain, nonatomic) NSArray *chatPanelModelArray;
@property (retain, nonatomic) UICollectionView *collectionView;
- (void)ahr_inject:(NSString *)from;   // %new
@end

// 远程图标缓存：异步下载 kAHRIconURL 存成 UIImage，供 cell 兜底直接塞（和 URL 主方案同一张图）。
static UIImage *gAHRRemoteIcon = nil;
static UIImage *AHRRemoteIcon(void) { return gAHRRemoteIcon; }

// 预热下载（只发一次）。下载完存缓存，下次 inject/layout 时 cell 兜底会用上。
static void AHRPreloadRemoteIcon(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            NSURL *u = [NSURL URLWithString:kAHRIconURL];
            if (!u) return;
            NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:u
                completionHandler:^(NSData *d, NSURLResponse *resp, NSError *err) {
                if (d.length) {
                    UIImage *im = [UIImage imageWithData:d];
                    if (im) dispatch_async(dispatch_get_main_queue(), ^{ gAHRRemoteIcon = im; });
                }
            }];
            [task resume];
        } @catch (__unused NSException *e) {}
    });
}

// 在 cell 里递归找第一个尺寸合适的 UIImageView（兜底直接塞图用）。
static UIImageView *AHRFindImageView(UIView *v) {
    if (!v) return nil;
    for (UIView *sub in v.subviews) {
        if ([sub isKindOfClass:UIImageView.class] &&
            sub.bounds.size.width >= 16 && sub.bounds.size.height >= 16)
            return (UIImageView *)sub;
        UIImageView *r = AHRFindImageView(sub);
        if (r) return r;
    }
    return nil;
}

%hook AWEIMPlusPanelView

%new
- (void)ahr_inject:(NSString *)from {
    @try {
        NSArray *arr = self.chatPanelModelArray;
        if (![arr isKindOfClass:[NSArray class]]) {
            NSLog(@"[CardAutoReply] inject(%@): chatPanelModelArray 非数组(%@)，跳过", from, [arr class]);
            return;
        }
        // 已含则跳过
        for (id m in arr) {
            @try { if ([[m valueForKey:@"labelText"] isEqualToString:kAHRPanelItemLabel]) return; }
            @catch (__unused NSException *e) {}
        }

        Class MC = objc_getClass("AWEIMChatPanelModel");
        if (!MC) { NSLog(@"[CardAutoReply] inject(%@): 无 AWEIMChatPanelModel 类", from); return; }

        AWEIMChatPanelModel *model = [[MC alloc] initWithDefault];
        if (!model) { NSLog(@"[CardAutoReply] inject(%@): 造 model 失败", from); return; }

        // 参考 DouyinHelper：不用平台模型，纯基础模型经典渲染（这样 iconUrl 才生效）。
        // 从一个「经典项」（无平台模型）拷 modelType，帮助渲染/点击匹配。
        AWEIMChatPanelModel *sibling = nil;
        for (id m in arr) {
            @try { if ([m isKindOfClass:MC] && ![(AWEIMChatPanelModel *)m platformChatPanelModel]) { sibling = m; break; } }
            @catch (__unused NSException *e) {}
        }
        if (sibling) model.modelType = sibling.modelType;

        model.isUnavailable = NO;
        model.labelText = kAHRPanelItemLabel;

        // 关键：图标 URL 设在【基础模型】的 iconUrlLight/Dark（逆向参考所得，真正生效的字段）
        @try {
            if ([model respondsToSelector:@selector(setIconUrlLight:)]) {
                ((void(*)(id, SEL, id))objc_msgSend)(model, @selector(setIconUrlLight:), kAHRIconURL);
                ((void(*)(id, SEL, id))objc_msgSend)(model, @selector(setIconUrlDark:),  kAHRIconURL);
            }
        } @catch (__unused NSException *e) {}

        // buttonImage 兜底：下载好的远程图（首次可能还没下完，下次 reload 生效）
        AHRPreloadRemoteIcon();
        UIImage *icon = AHRRemoteIcon();
        if (icon) model.buttonImage = icon;

        // 注意：不设 platformChatPanelModel —— 平台模型路径不读 iconUrl，会白块
        NSLog(@"[CardAutoReply] 注入(经典模式): label=%@ modelType=%llu icon=%@",
              kAHRPanelItemLabel, (unsigned long long)model.modelType, kAHRIconURL);

        model.didSelectedAction = ^{
            NSLog(@"[CardAutoReply] 面板项被点击，打开设置");
            Class ed = objc_getClass("AHRCardAutoReplyEditor");
            if ([ed respondsToSelector:@selector(present)])
                ((void(*)(id, SEL))objc_msgSend)(ed, @selector(present));
        };

        self.chatPanelModelArray = [arr arrayByAddingObject:model];
        NSLog(@"[CardAutoReply] inject(%@): 已追加，count %lu -> %lu (sibling modelType=%llu/%llu)",
              from, (unsigned long)arr.count, (unsigned long)self.chatPanelModelArray.count,
              (unsigned long long)model.modelType, (unsigned long long)model.platformModelType);
        [self.collectionView reloadData];
    } @catch (NSException *e) {
        NSLog(@"[CardAutoReply] inject(%@) 异常: %@", from, e);
    }
}

- (void)reloadData {
    %orig;
    [self ahr_inject:@"reloadData"];
}

- (void)reloadDataWithPlatformChatPanelModels {
    %orig;
    [self ahr_inject:@"reloadDataWithPlatform"];
}

- (void)updateDataSource:(id)a0 {
    %orig;
    [self ahr_inject:@"updateDataSource"];
}

- (void)layoutSubviews {
    %orig;
    [self ahr_inject:@"layoutSubviews"];
}

- (unsigned long long)numberOfItemsInChatPanel {
    unsigned long long n = %orig;
    static BOOL logged = NO;
    if (!logged) {
        logged = YES;
        NSLog(@"[CardAutoReply] numberOfItemsInChatPanel=%llu, arrayCount=%lu",
              n, (unsigned long)self.chatPanelModelArray.count);
    }
    return n;
}

// 兜底：cell 渲染出来后，直接给我们那格的 imageView 塞图，绕过 URL 加载器（修白块）
- (id)collectionView:(id)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
    id cell = %orig;
    @try {
        NSArray *arr = self.chatPanelModelArray;
        long long idx = ip.item;
        if ([self respondsToSelector:@selector(realItemIndexFromIndexPath:)])
            idx = ((long long(*)(id, SEL, id))objc_msgSend)(self, @selector(realItemIndexFromIndexPath:), ip);
        if (idx >= 0 && idx < (long long)arr.count) {
            id m = arr[idx];
            if ([[m valueForKey:@"labelText"] isEqualToString:kAHRPanelItemLabel] &&
                [cell isKindOfClass:UIView.class]) {
                UIView *root = [cell respondsToSelector:@selector(contentView)] ? [cell contentView] : cell;
                UIImageView *iv = AHRFindImageView(root);
                UIImage *img = AHRRemoteIcon();          // 下载好的远程图；没下完则先靠 URL 加载器
                if (iv && img) {
                    iv.image = img;
                    iv.contentMode = UIViewContentModeScaleAspectFit;
                    iv.hidden = NO;
                }
            }
        }
    } @catch (__unused NSException *e) {}
    return cell;
}

// 兜底：即便原生 didSelect 未回调 didSelectedAction，这里也保证点击生效
- (void)collectionView:(id)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    @try {
        NSArray *arr = self.chatPanelModelArray;
        long long idx = ip.item;
        if ([self respondsToSelector:@selector(realItemIndexFromIndexPath:)])
            idx = ((long long(*)(id, SEL, id))objc_msgSend)(self, @selector(realItemIndexFromIndexPath:), ip);
        if (idx >= 0 && idx < (long long)arr.count) {
            id m = arr[idx];
            if ([[m valueForKey:@"labelText"] isEqualToString:kAHRPanelItemLabel]) {
                id block = [m valueForKey:@"didSelectedAction"];
                if (block) ((void(^)(void))block)();
                return;
            }
        }
    } @catch (__unused NSException *e) {}
    %orig;
}

%end
