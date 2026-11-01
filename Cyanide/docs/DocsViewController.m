//
//  DocsViewController.m
//  Cyanide
//

#import "DocsViewController.h"

#pragma mark - DocsSectionHeader

@interface DocsSectionHeader : UITableViewHeaderFooterView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
- (void)configureWithSymbol:(NSString *)symbolName tint:(UIColor *)tint title:(NSString *)title;
@end

@implementation DocsSectionHeader

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    UIView *bg = [[UIView alloc] init];
    bg.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.backgroundView = bg;

    _iconView = [[UIImageView alloc] init];
    _iconView.translatesAutoresizingMaskIntoConstraints = NO;
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = UIColor.labelColor;
    [self.contentView addSubview:_iconView];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _titleLabel.adjustsFontForContentSizeCategory = YES;
    _titleLabel.textColor = UIColor.labelColor;
    _titleLabel.numberOfLines = 0;
    [self.contentView addSubview:_titleLabel];

    [_iconView setContentHuggingPriority:UILayoutPriorityRequired
                                 forAxis:UILayoutConstraintAxisHorizontal];
    [_iconView setContentCompressionResistancePriority:UILayoutPriorityRequired
                                               forAxis:UILayoutConstraintAxisHorizontal];

    [NSLayoutConstraint activateConstraints:@[
        [_iconView.leadingAnchor    constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_iconView.centerYAnchor    constraintEqualToAnchor:_titleLabel.firstBaselineAnchor constant:-6.0],

        [_titleLabel.leadingAnchor  constraintEqualToAnchor:_iconView.trailingAnchor constant:10.0],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_titleLabel.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor    constant:14.0],
        [_titleLabel.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor constant:-6.0],
    ]];
    return self;
}

- (void)configureWithSymbol:(NSString *)symbolName tint:(UIColor *)tint title:(NSString *)title
{
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithFont:self.titleLabel.font
                                                    scale:UIImageSymbolScaleSmall];
    self.iconView.image = [UIImage systemImageNamed:symbolName withConfiguration:cfg];
    self.iconView.tintColor = tint;
    self.titleLabel.text = title;
}

@end

#pragma mark - DocsFooter

@interface DocsFooter : UITableViewHeaderFooterView
@property (nonatomic, strong) UILabel *body;
- (void)configureWithText:(NSString *)text;
@end

@implementation DocsFooter

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithReuseIdentifier:reuseIdentifier];
    if (!self) return nil;
    UIView *bg = [[UIView alloc] init];
    bg.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.backgroundView = bg;

    _body = [[UILabel alloc] init];
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    _body.numberOfLines = 0;
    _body.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _body.adjustsFontForContentSizeCategory = YES;
    _body.textColor = UIColor.secondaryLabelColor;
    [self.contentView addSubview:_body];

    [NSLayoutConstraint activateConstraints:@[
        [_body.leadingAnchor  constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
        [_body.trailingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
        [_body.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor    constant:8.0],
        [_body.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor constant:-18.0],
    ]];
    return self;
}

- (void)configureWithText:(NSString *)text { self.body.text = text; }

@end

#pragma mark - DocsCell

@interface DocsCell : UITableViewCell
@property (nonatomic, strong) UITextView *body;
@property (nonatomic, strong) UIView *codeBackground;
@property (nonatomic, strong) UILabel *filenameLabel;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) NSLayoutConstraint *dividerHeight;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *proseConstraints;
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *codeConstraints;
- (void)configureProseWithText:(NSString *)text;
- (void)configureCodeWithText:(NSString *)text filename:(NSString *)filename;
@end

@implementation DocsCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (!self) return nil;

    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.contentView.backgroundColor = UIColor.clearColor;

    _codeBackground = [[UIView alloc] init];
    _codeBackground.translatesAutoresizingMaskIntoConstraints = NO;
    _codeBackground.backgroundColor = UIColor.tertiarySystemGroupedBackgroundColor;
    _codeBackground.layer.cornerRadius = 10.0;
    _codeBackground.layer.cornerCurve = kCACornerCurveContinuous;
    _codeBackground.layer.masksToBounds = YES;
    _codeBackground.hidden = YES;
    [self.contentView addSubview:_codeBackground];

    _filenameLabel = [[UILabel alloc] init];
    _filenameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _filenameLabel.font = [UIFont monospacedSystemFontOfSize:11.0 weight:UIFontWeightMedium];
    _filenameLabel.textColor = UIColor.secondaryLabelColor;
    [_codeBackground addSubview:_filenameLabel];

    _divider = [[UIView alloc] init];
    _divider.translatesAutoresizingMaskIntoConstraints = NO;
    _divider.backgroundColor = UIColor.separatorColor;
    [_codeBackground addSubview:_divider];
    _dividerHeight = [_divider.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale];

    _body = [[UITextView alloc] init];
    _body.translatesAutoresizingMaskIntoConstraints = NO;
    _body.scrollEnabled = NO;
    _body.editable = NO;
    _body.backgroundColor = UIColor.clearColor;
    _body.textContainerInset = UIEdgeInsetsZero;
    _body.textContainer.lineFragmentPadding = 0.0;
    _body.dataDetectorTypes = UIDataDetectorTypeLink;
    _body.linkTextAttributes = @{ NSForegroundColorAttributeName: UIColor.systemBlueColor };
    _body.adjustsFontForContentSizeCategory = YES;
    _body.alwaysBounceVertical = NO;
    [self.contentView addSubview:_body];

    _proseConstraints = @[
        [_body.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor      constant:9.0],
        [_body.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor   constant:-9.0],
        [_body.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor  constant:18.0],
        [_body.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-18.0],
    ];
    _codeConstraints = @[
        [_codeBackground.topAnchor      constraintEqualToAnchor:self.contentView.topAnchor      constant:6.0],
        [_codeBackground.bottomAnchor   constraintEqualToAnchor:self.contentView.bottomAnchor   constant:-6.0],
        [_codeBackground.leadingAnchor  constraintEqualToAnchor:self.contentView.leadingAnchor  constant:12.0],
        [_codeBackground.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12.0],

        [_filenameLabel.topAnchor              constraintEqualToAnchor:_codeBackground.topAnchor      constant:9.0],
        [_filenameLabel.leadingAnchor          constraintEqualToAnchor:_codeBackground.leadingAnchor  constant:14.0],
        [_filenameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_codeBackground.trailingAnchor constant:-14.0],

        [_divider.topAnchor       constraintEqualToAnchor:_filenameLabel.bottomAnchor constant:8.0],
        [_divider.leadingAnchor   constraintEqualToAnchor:_codeBackground.leadingAnchor],
        [_divider.trailingAnchor  constraintEqualToAnchor:_codeBackground.trailingAnchor],
        _dividerHeight,

        [_body.topAnchor      constraintEqualToAnchor:_divider.bottomAnchor           constant:10.0],
        [_body.bottomAnchor   constraintEqualToAnchor:_codeBackground.bottomAnchor    constant:-12.0],
        [_body.leadingAnchor  constraintEqualToAnchor:_codeBackground.leadingAnchor   constant:14.0],
        [_body.trailingAnchor constraintEqualToAnchor:_codeBackground.trailingAnchor  constant:-14.0],
    ];
    return self;
}

- (void)configureProseWithText:(NSString *)text
{
    [NSLayoutConstraint deactivateConstraints:_codeConstraints];
    [NSLayoutConstraint activateConstraints:_proseConstraints];
    _codeBackground.hidden = YES;
    _body.textContainer.maximumNumberOfLines = 0;
    _body.textContainer.lineBreakMode = NSLineBreakByWordWrapping;

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 3.0;
    para.paragraphSpacing = 10.0;
    _body.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: para,
    }];
}

- (void)configureCodeWithText:(NSString *)text filename:(NSString *)filename
{
    [NSLayoutConstraint deactivateConstraints:_proseConstraints];
    [NSLayoutConstraint activateConstraints:_codeConstraints];
    _codeBackground.hidden = NO;
    _filenameLabel.text = filename ?: @"";
    _dividerHeight.constant = 1.0 / UIScreen.mainScreen.scale;
    _body.textContainer.maximumNumberOfLines = 0;
    _body.textContainer.lineBreakMode = NSLineBreakByWordWrapping;

    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = 2.0;
    UIFont *baseMono = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    UIFont *mono = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleFootnote] scaledFontForFont:baseMono];
    _body.attributedText = [[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: mono,
        NSForegroundColorAttributeName: UIColor.labelColor,
        NSParagraphStyleAttributeName: para,
    }];
}

@end

#pragma mark - DocsViewController

static NSString * const kProseCellID   = @"DocsProseCell";
static NSString * const kCodeCellID    = @"DocsCodeCell";
static NSString * const kHeaderID      = @"DocsSectionHeader";
static NSString * const kFooterID      = @"DocsFooter";

@interface DocsViewController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *sections;
@end

@implementation DocsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.title = @"Docs";
    self.navigationItem.title = @"Docs";

    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 80.0;
    self.tableView.estimatedSectionHeaderHeight = 60.0;
    self.tableView.estimatedSectionFooterHeight = 40.0;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.contentInset = UIEdgeInsetsMake(0, 0, 28, 0);
    if (@available(iOS 15.0, *)) {
        self.tableView.sectionHeaderTopPadding = 6.0;
    }
    [self.tableView registerClass:DocsCell.class           forCellReuseIdentifier:kProseCellID];
    [self.tableView registerClass:DocsCell.class           forCellReuseIdentifier:kCodeCellID];
    [self.tableView registerClass:DocsSectionHeader.class  forHeaderFooterViewReuseIdentifier:kHeaderID];
    [self.tableView registerClass:DocsFooter.class         forHeaderFooterViewReuseIdentifier:kFooterID];

    [self buildSections];
}

#pragma mark - Content

- (void)buildSections
{
    NSString *helloHeader =
        @"#ifndef hello_tweak_h\n"
        @"#define hello_tweak_h\n"
        @"#include <stdbool.h>\n"
        @"bool hello_tweak_apply_in_session(void);\n"
        @"bool hello_tweak_stop_in_session(void);\n"
        @"void hello_tweak_forget_remote_state(void);\n"
        @"#endif";

    NSString *helloImpl =
        @"#import \"hello_tweak.h\"\n"
        @"#import \"remote_objc.h\"\n"
        @"#import \"../TaskRop/RemoteCall.h\"\n"
        @"#import <stdint.h>\n"
        @"\n"
        @"static const uint64_t kHelloTag = 0xC0A11DE;\n"
        @"static uint64_t gHelloView = 0;\n"
        @"\n"
        @"static uint64_t hello_first_window(void) {\n"
        @"    uint64_t UIApplication = r_class(\"UIApplication\");\n"
        @"    uint64_t app = r_msg2_main(UIApplication, \"sharedApplication\",\n"
        @"                               0, 0, 0, 0);\n"
        @"    if (!r_is_objc_ptr(app)) return 0;\n"
        @"\n"
        @"    uint64_t keyWindow = r_msg2_main(app, \"keyWindow\", 0, 0, 0, 0);\n"
        @"    if (r_is_objc_ptr(keyWindow)) return keyWindow;\n"
        @"\n"
        @"    uint64_t windows = r_msg2_main(app, \"windows\", 0, 0, 0, 0);\n"
        @"    uint64_t count = r_msg2_main(windows, \"count\", 0, 0, 0, 0);\n"
        @"    for (uint64_t i = 0; r_is_objc_ptr(windows) && i < count && i < 16; i++) {\n"
        @"        uint64_t window = r_msg2_main(windows, \"objectAtIndex:\", i, 0, 0, 0);\n"
        @"        if (r_is_objc_ptr(window)) return window;\n"
        @"    }\n"
        @"    return 0;\n"
        @"}\n"
        @"\n"
        @"static uint64_t hello_existing_view(uint64_t window) {\n"
        @"    if (!r_is_objc_ptr(window)) return 0;\n"
        @"    uint64_t view = r_msg2_main(window, \"viewWithTag:\", kHelloTag, 0, 0, 0);\n"
        @"    if (r_is_objc_ptr(view)) gHelloView = view;\n"
        @"    return r_is_objc_ptr(view) ? view : 0;\n"
        @"}\n"
        @"\n"
        @"bool hello_tweak_apply_in_session(void) {\n"
        @"    uint64_t window = hello_first_window();\n"
        @"    if (!r_is_objc_ptr(window)) return false;\n"
        @"\n"
        @"    uint64_t existing = hello_existing_view(window);\n"
        @"    if (r_is_objc_ptr(existing)) {\n"
        @"        r_msg2_main(existing, \"setHidden:\", 0, 0, 0, 0);\n"
        @"        r_msg2_main(window, \"bringSubviewToFront:\", existing, 0, 0, 0);\n"
        @"        return true;\n"
        @"    }\n"
        @"\n"
        @"    uint64_t UIView = r_class(\"UIView\");\n"
        @"    uint64_t view = r_msg2_main(r_msg2_main(UIView, \"alloc\", 0, 0, 0, 0),\n"
        @"                                \"init\", 0, 0, 0, 0);\n"
        @"    if (!r_is_objc_ptr(view)) return false;\n"
        @"\n"
        @"    struct { double x, y, w, h; } frame = { 40.0, 120.0, 80.0, 80.0 };\n"
        @"    r_msg2_main_raw(view, \"setFrame:\",\n"
        @"                    &frame, sizeof(frame),\n"
        @"                    NULL, 0, NULL, 0, NULL, 0);\n"
        @"\n"
        @"    uint64_t UIColor = r_class(\"UIColor\");\n"
        @"    uint64_t color = r_msg2_main(UIColor, \"systemRedColor\", 0, 0, 0, 0);\n"
        @"    if (!r_is_objc_ptr(color)) color = r_msg2_main(UIColor, \"redColor\", 0, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"setBackgroundColor:\", color, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"setTag:\", kHelloTag, 0, 0, 0);\n"
        @"    r_msg2_main(window, \"addSubview:\", view, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"release\", 0, 0, 0, 0);\n"
        @"\n"
        @"    gHelloView = view;\n"
        @"    return true;\n"
        @"}\n"
        @"\n"
        @"bool hello_tweak_stop_in_session(void) {\n"
        @"    uint64_t window = hello_first_window();\n"
        @"    uint64_t view = hello_existing_view(window);\n"
        @"    if (!r_is_objc_ptr(view)) return false;\n"
        @"\n"
        @"    r_msg2_main(view, \"setHidden:\", 1, 0, 0, 0);\n"
        @"    r_msg2_main(view, \"removeFromSuperview\", 0, 0, 0, 0);\n"
        @"    gHelloView = 0;\n"
        @"    return true;\n"
        @"}\n"
        @"\n"
        @"void hello_tweak_forget_remote_state(void) {\n"
        @"    // SpringBoard respawned or RemoteCall was abandoned; cached\n"
        @"    // remote pointers are from the old address space.\n"
        @"    gHelloView = 0;\n"
        @"}";

    NSString *wiring =
        @"#import \"tweaks/hello_tweak.h\"\n"
        @"NSString * const kSettingsHelloEnabled = @\"HelloEnabled\";\n"
        @"\n"
        @"// Add kSettingsHelloEnabled to settings_register_defaults(),\n"
        @"// settings_rc_backed_tweak_keys(), settings_key_affects_package_state(),\n"
        @"// and the Settings rows that render the switch.\n"
        @"static BOOL settings_key_is_hello(NSString *key) {\n"
        @"    return [key isEqualToString:kSettingsHelloEnabled];\n"
        @"}\n"
        @"\n"
        @"// In the Run path, after settings_ensure_springboard_remote_call_locked():\n"
        @"if ([d boolForKey:kSettingsHelloEnabled]) {\n"
        @"    bool ok = hello_tweak_apply_in_session();\n"
        @"    settings_mark_tweak_applied(kSettingsHelloEnabled,\n"
        @"                                ok && [d boolForKey:kSettingsHelloEnabled]);\n"
        @"    printf(\"[SETTINGS] Hello result=%d\\n\", ok);\n"
        @"}\n"
        @"\n"
        @"// In settings_schedule_live_apply_for_key():\n"
        @"if (settings_key_is_hello(key)) {\n"
        @"    if ([d boolForKey:kSettingsHelloEnabled] && g_springboard_rc_ready) {\n"
        @"        dispatch_async(dispatch_get_global_queue(0, 0), ^{\n"
        @"            @synchronized (settings_rc_lock()) {\n"
        @"                if (settings_cleanup_in_progress() || !g_springboard_rc_ready) return;\n"
        @"                bool ok = hello_tweak_apply_in_session();\n"
        @"                settings_mark_tweak_applied(kSettingsHelloEnabled,\n"
        @"                                            ok && [d boolForKey:kSettingsHelloEnabled]);\n"
        @"            }\n"
        @"            settings_notify_package_queue_changed_async();\n"
        @"        });\n"
        @"    } else if (![d boolForKey:kSettingsHelloEnabled]) {\n"
        @"        settings_mark_tweak_applied(kSettingsHelloEnabled, NO);\n"
        @"        settings_notify_package_queue_changed_async();\n"
        @"        if (g_springboard_rc_ready) dispatch_async(dispatch_get_global_queue(0, 0), ^{\n"
        @"            @synchronized (settings_rc_lock()) {\n"
        @"                if (g_springboard_rc_ready) hello_tweak_stop_in_session();\n"
        @"            }\n"
        @"        });\n"
        @"    }\n"
        @"    return;\n"
        @"}\n"
        @"\n"
        @"// In SpringBoard restart/abandon and manual cleanup paths:\n"
        @"hello_tweak_forget_remote_state();";

    NSString *apiCheat =
        @"#import \"remote_objc.h\"\n"
        @"#import \"../TaskRop/RemoteCall.h\"\n"
        @"\n"
        @"r_class(\"UILabel\")                  // remote Class *\n"
        @"r_sel(\"setHidden:\")                 // remote SEL\n"
        @"r_msg2(obj, \"setHidden:\", 1,0,0,0)  // objc_msgSend in target\n"
        @"r_msg2_main(label, \"setText:\", text,\n"
        @"            0,0,0)                   // UIKit/main-thread send\n"
        @"r_msg2_main_raw(obj, \"setFrame:\",\n"
        @"  &rect, sizeof(rect), NULL,0,\n"
        @"  NULL,0, NULL,0)                    // pass a struct by value\n"
        @"r_msg2_main_struct_ret(obj, \"bounds\",\n"
        @"  &out, sizeof(out), NULL,0,\n"
        @"  NULL,0, NULL,0, NULL,0)            // copy a struct return\n"
        @"\n"
        @"r_alloc_str(\"hi\") / r_free(ptr)     // C string into remote\n"
        @"r_nsstr_retained(\"hi\")              // NSString*, caller releases\n"
        @"r_cfstr(\"hi\")                       // CFStringRef, caller CFReleases\n"
        @"r_settle_us(1000)                    // tune helper delay; restore old value\n"
        @"\n"
        @"r_dlsym_call(R_TIMEOUT,\n"
        @"  \"objc_setAssociatedObject\",\n"
        @"  obj, key, val, policy, 0,0,0,0)    // any C function\n"
        @"r_is_objc_ptr(p)                     // sanity check\n"
        @"r_ivar_value(obj, \"_name\")          // read ivar\n"
        @"r_responds_main(obj, \"sel:\")        // -respondsToSelector:\n"
        @"remote_read / remote_write           // raw memory helpers\n"
        @"init_remote_call(\"SpringBoard\", false)\n"
        @"destroy_remote_call()                // one-shot sessions only\n"
        @"abandon_remote_call()                // remote task is already gone";

    NSString *portingNotes =
        @"%hook UIView                         not portable as a hook\n"
        @"- (void)setHidden:(BOOL)h { ... }    rewrite as explicit\n"
        @"                                     r_msg2_main(view,\n"
        @"                                     \"setHidden:\", h,0,0,0)\n"
        @"\n"
        @"[%c(Foo) bar]                        r_msg2(r_class(\"Foo\"),\n"
        @"                                           \"bar\", 0,0,0,0)\n"
        @"\n"
        @"struct { double x,y,w,h; } r = {0};  r_msg2_main_struct_ret(view,\n"
        @"                                     \"bounds\", &r, sizeof(r),\n"
        @"                                     NULL,0, NULL,0, NULL,0, NULL,0)\n"
        @"\n"
        @"%new -[X cyanideOverlay]             associated object via\n"
        @"                                     objc_setAssociatedObject\n"
        @"                                     through r_dlsym_call\n"
        @"\n"
        @"MSHookFunction(...)                  not available here";

    self.sections = @[
        @{ @"title": @"插件是如何工作的",
           @"symbol": @"book.closed.fill",
           @"tint": UIColor.systemPurpleColor,
           @"footer": @"请阅读 Cyanide/tweaks/ 中的 sbcustomizer.m、statbar.m 与 axonlite.m，"
                      @"它们按复杂度由低到高展示了已提供的示例模式。",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"Cyanide 的插件是应用侧的驱动程序。没有 SpringBoard 动态库，也没有"
                           @"Substrate 钩子，更没有方法交换（swizzle）。应用从外部"
                           @"侵入目标进程。" },
               @{ @"kind": @"prose",
                  @"text": @"RemoteCall 会话就是那座桥。在会话内部，你可以发送"
                           @"Objective-C 消息、读写内存，并调用目标进程中的 C 符号，"
                           @"这些都在目标进程里完成。" },
               @{ @"kind": @"prose",
                  @"text": @"在「应用插件」期间，设置页持有通往 SpringBoard 的通道。你的"
                           @"代码在 settings_rc_lock() 保护下于其中运行，通过三个"
                           @"入口点执行：apply_in_session、可选的 stop_in_session，以及"
                           @"forget_remote_state。" },
           ]},

        @{ @"title": @"remote_objc API",
           @"symbol": @"chevron.left.forwardslash.chevron.right",
           @"tint": UIColor.systemBlueColor,
           @"footer": @"_main 系列会把调用派发到目标进程的主线程（涉及 UIKit 的调用请用"
                      @"它们）。_raw 按值传递非指针参数。"
                      @"r_msg2_main_struct_ret 用于拷贝诸如 CGRect 这样的结构体返回值。",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"请导入 remote_objc.h 与 ../TaskRop/RemoteCall.h。这些辅助函数假定"
                           @"已存在一个活动会话——除非你需要一条私有通道，否则不要自己调用"
                           @"init_remote_call。" },
               @{ @"kind": @"code", @"filename": @"remote_objc.h", @"text": apiCheat },
           ]},

        @{ @"title": @"一个最小化的插件",
           @"symbol": @"doc.text.fill",
           @"tint": UIColor.systemOrangeColor,
           @"footer": @"把这两个文件放进 Cyanide/tweaks/。Xcode 工程使用"
                      @"PBXFileSystemSynchronizedRootGroup，因此新文件会被"
                      @"自动纳入——无需手动编辑 pbxproj。",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"一个纯 RemoteCall 的完整插件：在 SpringBoard 窗口上"
                           @"绘制一个 80×80 的红色方块。" },
               @{ @"kind": @"prose",
                  @"text": @"重复应用是幂等的，停止时会自行撤销，并在进程"
                           @"重生（respawn）时丢弃缓存的指针。" },
               @{ @"kind": @"code", @"filename": @"hello_tweak.h", @"text": helloHeader },
               @{ @"kind": @"code", @"filename": @"hello_tweak.m", @"text": helloImpl },
           ]},

        @{ @"title": @"接入设置页",
           @"symbol": @"gearshape.2.fill",
           @"tint": UIColor.systemGreenColor,
           @"footer": @"参照已有的 kSettings…Enabled 路径——搜索"
                      @"kSettingsStatBarEnabled 或 kSettingsAxonLiteEnabled，即可得到一份完整的"
                      @"模板，涵盖默认值、开关行、软件包状态、运行（Run）、实时应用、"
                      @"停止与清理。",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"SettingsViewController.m 是总调度者。你需要添加五样东西：一个"
                           @"默认值键、一个开关行、一个运行期应用、一个实时应用"
                           @"分支，以及清理时的 forget_remote_state。" },
               @{ @"kind": @"prose",
                  @"text": @"每次应用都会在 @synchronized(settings_rc_lock()) 内部检查"
                           @"g_springboard_rc_ready。settings_mark_tweak_applied() 用来"
                           @"保证软件包状态真实可信。forget_remote_state() 会在"
                           @"respring 与连接放弃（abandon）时运行。" },
               @{ @"kind": @"code", @"filename": @"SettingsViewController.m", @"text": wiring },
           ]},

        @{ @"title": @"从 Theos / Substrate 移植",
           @"symbol": @"arrow.triangle.2.circlepath",
           @"tint": UIColor.systemPinkColor,
           @"footer": @"已提供的模板：sbcustomizer（Dock 布局）、darksword_tweaks"
                      @"（SpringBoard 状态开关）、powercuff（thermalmonitord 一次性任务）、"
                      @"statbar（悬浮窗）、"
                      @"axonlite（缓存的通知中心状态）。",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"RemoteCall 不是钩子框架。你无法拦截某个方法"
                           @"或在原地替换一个 C 函数。" },
               @{ @"kind": @"prose",
                  @"text": @"当效果是一种有限的变更时，移植才可行——例如设置这个"
                           @"属性、调用这个控制器方法、添加这个视图、保持这个"
                           @"断言，或按定时器刷新。" },
               @{ @"kind": @"code", @"filename": @"Theos → RemoteCall", @"text": portingNotes },
               @{ @"kind": @"prose",
                  @"text": @"想针对另一个进程？用 init_remote_call(name, false) 开启一个独立会话，"
                           @"完成工作后，在切回之前调用 destroy_remote_call"
                           @"将其销毁。Powercuff 就是针对 thermalmonitord 这么做的。" },
           ]},

        @{ @"title": @"参与贡献",
           @"symbol": @"arrow.up.right.square.fill",
           @"tint": UIColor.systemRedColor,
           @"footer": @"",
           @"rows": @[
               @{ @"kind": @"prose",
                  @"text": @"用 ./scripts/build.sh 构建——IPA 会被打包到"
                           @"build/ 目录下。侧载到设备上进行测试，把「日志」标签页的输出附到你的"
                           @"PR 里。" },
               @{ @"kind": @"prose",
                  @"text": @"源码与问题反馈：https://github.com/kolbicz/cyanide" },
           ]},
    ];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *rows = self.sections[section][@"rows"];
    return (NSInteger)rows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *kind = row[@"kind"];
    NSString *text = row[@"text"];
    BOOL isCode = [kind isEqualToString:@"code"];

    DocsCell *cell = [tableView dequeueReusableCellWithIdentifier:isCode ? kCodeCellID : kProseCellID
                                                     forIndexPath:indexPath];
    if (isCode) {
        [cell configureCodeWithText:text filename:row[@"filename"]];
    } else {
        [cell configureProseWithText:text];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    NSDictionary *info = self.sections[section];
    DocsSectionHeader *header = [tableView dequeueReusableHeaderFooterViewWithIdentifier:kHeaderID];
    [header configureWithSymbol:info[@"symbol"] tint:info[@"tint"] title:info[@"title"]];
    return header;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    NSString *text = self.sections[section][@"footer"];
    if (text.length == 0) return nil;
    DocsFooter *footer = [tableView dequeueReusableHeaderFooterViewWithIdentifier:kFooterID];
    [footer configureWithText:text];
    return footer;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    NSString *text = self.sections[section][@"footer"];
    return text.length == 0 ? CGFLOAT_MIN : UITableViewAutomaticDimension;
}

@end
