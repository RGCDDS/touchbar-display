//
//  TBWeatherService.m
//
//  两条取坐标的路：
//    1) 设置里填了城市 → Open-Meteo geocoding（免 key，支持中文）
//    2) 没填 → CoreLocation 定位（首次会弹系统授权框）
//  拿到坐标后统一打 Open-Meteo 的 current 接口，把 WMO weather_code + 风速映射成 晴/风/雨。
//

#import "TBWeatherService.h"
#import <CoreLocation/CoreLocation.h>

static NSString * const kGeoSearchURL = @"https://geocoding-api.open-meteo.com/v1/search";
static NSString * const kForecastURL  = @"https://api.open-meteo.com/v1/forecast";

/// 风速超过这个值（m/s）就当"风"。5.5 m/s ≈ 20 km/h ≈ 4 级风
static const double kWindThreshold = 5.5;
/// 云量 ≥ 这个值算"厚云"（武汉实测：88–100 占了白天 58%，中间带几乎没有）
static const double kOvercastCloud = 88.0;
/// 厚云时，如果白天平均日照辐射还有这么高，说明云层薄、透着光，仍按晴处理
static const double kBrightRadiation = 300.0;

#pragma mark - 天空分级

typedef NS_ENUM(NSInteger, TBSkyGrade) {
    TBSkyGradeClear = 0,       // 大晴
    TBSkyGradePartly,          // 晴间多云
    TBSkyGradeLightOvercast,   // 小阴
    TBSkyGradeMidOvercast,     // 中阴（厚云但透光）
    TBSkyGradeHeavyOvercast,   // 大阴
};

static NSString *TBGradeName(TBSkyGrade g) {
    switch (g) {
        case TBSkyGradeClear:        return @"大晴";
        case TBSkyGradePartly:       return @"晴间多云";
        case TBSkyGradeLightOvercast:return @"小阴";
        case TBSkyGradeMidOvercast:  return @"中阴";
        case TBSkyGradeHeavyOvercast:return @"大阴";
    }
    return @"";
}

/// dayRad = 当天 9:00–16:00 的平均日照辐射（W/m²），用平均值而不是瞬时值，
/// 否则早上和傍晚辐射天然低，一天里会反复横跳。
static TBSkyGrade TBGradeFor(double cloud, double dayRad, BOOL night) {
    if (cloud < 30) return TBSkyGradeClear;
    if (cloud < 60) return TBSkyGradePartly;
    if (cloud < kOvercastCloud) return TBSkyGradeLightOvercast;
    if (!night && dayRad >= kBrightRadiation) return TBSkyGradeMidOvercast;
    return TBSkyGradeHeavyOvercast;
}

/// 只有"大阴"用风那套（云在动，配阴沉的天），其余都用晴
static TBWeather TBWeatherForGrade(TBSkyGrade g) {
    return (g == TBSkyGradeHeavyOvercast) ? TBWeatherFeng : TBWeatherQing;
}

/// 从 hourly 里取当天 9–16 点的平均短波辐射
static double TBDaylightRadiation(NSDictionary *hourly) {
    NSArray *times = hourly[@"time"];
    NSArray *rads  = hourly[@"shortwave_radiation"];
    if (![times isKindOfClass:[NSArray class]] || ![rads isKindOfClass:[NSArray class]]) return 0;

    double sum = 0;
    int n = 0;
    NSUInteger cnt = MIN(times.count, rads.count);
    for (NSUInteger i = 0; i < cnt; i++) {
        id t = times[i], r = rads[i];
        if (![t isKindOfClass:[NSString class]] || [(NSString *)t length] < 13) continue;
        NSInteger hour = [[(NSString *)t substringWithRange:NSMakeRange(11, 2)] integerValue];
        if (hour < 9 || hour > 16) continue;
        if (![r isKindOfClass:[NSNumber class]]) continue;
        sum += [r doubleValue];
        n++;
    }
    return n ? sum / n : 0;
}

#pragma mark - WMO 天气码

static NSString *TBDescribeWMO(int code) {
    if (code == 0)  return @"晴";
    if (code == 1)  return @"晴间多云";
    if (code == 2)  return @"多云";
    if (code == 3)  return @"阴";
    if (code == 45 || code == 48) return @"雾";
    if (code >= 51 && code <= 57) return @"毛毛雨";
    if (code >= 61 && code <= 65) return @"雨";
    if (code == 66 || code == 67) return @"冻雨";
    if (code >= 71 && code <= 77) return @"雪";
    if (code >= 80 && code <= 82) return @"阵雨";
    if (code == 85 || code == 86) return @"阵雪";
    if (code == 95) return @"雷阵雨";
    if (code >= 96) return @"雷暴";
    return @"未知";
}

/// 降水优先，其次看风，剩下按"天空分级"决定用晴还是风
static TBWeather TBWeatherFromWMO(int code, double windMS,
                                  double cloud, double dayRad, BOOL night) {
    BOOL precip = (code >= 51 && code <= 67) ||
                  (code >= 71 && code <= 77) ||
                  (code >= 80 && code <= 86) ||
                  (code >= 95);
    if (precip) return TBWeatherYu;
    if (windMS >= kWindThreshold) return TBWeatherFeng;
    return TBWeatherForGrade(TBGradeFor(cloud, dayRad, night));
}

#pragma mark -

@interface TBWeatherService () <CLLocationManagerDelegate>
@property (nonatomic, assign) TBWeather weather;
@property (nonatomic, copy) NSString *status;

@property (nonatomic, strong) CLLocationManager *lm;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL authRequested;   // 本次运行只请求一次，别反复骚扰
@property (nonatomic, assign) BOOL weatherKnown;    // 成功拿到过一次，之后失败就不覆盖状态
@property (nonatomic, assign) NSInteger retryCount;     // 失败重试次数（指数退避）
@property (nonatomic, copy) NSString *placeName;
@end

@implementation TBWeatherService

+ (instancetype)shared {
    static TBWeatherService *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [TBWeatherService new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        _weather = TBWeatherQing;
        _status = @"尚未获取";
    }
    return self;
}

#pragma mark - 对外

- (void)startWithInterval:(NSTimeInterval)seconds {
    [self stop];
    [self refresh];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:MAX(60.0, seconds)
                                                  target:self
                                                selector:@selector(refresh)
                                                userInfo:nil
                                                 repeats:YES];
    self.timer.tolerance = 30;
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
    [self.lm stopUpdatingLocation];
}

- (void)refresh {
    if (self.busy) return;

    NSString *city = [[TBSettings shared] weatherCity];
    if (city.length > 0) {
        [self fetchByCity:city];
        return;
    }
    [self fetchByLocation];
}

#pragma mark - 定位

- (void)fetchByLocation {
    if (!self.lm) {
        self.lm = [CLLocationManager new];
        self.lm.delegate = self;
        self.lm.desiredAccuracy = kCLLocationAccuracyKilometer;   // 城市级就够
    }

    CLAuthorizationStatus st = self.lm.authorizationStatus;
    if (st == kCLAuthorizationStatusNotDetermined) {
        // 只在本次运行第一次尝试时弹系统授权框。
        // 反复 build 会让签名哈希变、系统当成新 App 重新问——所以定位成功一次就把城市名记下来，
        // 以后都走城市名，永远不再碰定位。
        if (self.authRequested) {
            [self publishStatus:@"还没授权定位，请在设置里填个城市名"];
            return;
        }
        self.authRequested = YES;
        self.busy = YES;
        [self publishStatus:@"正在请求定位授权…"];
        [self.lm requestWhenInUseAuthorization];
        return;
    }
    if (st == kCLAuthorizationStatusDenied || st == kCLAuthorizationStatusRestricted) {
        [self publishStatus:@"定位被拒绝，请在设置里填城市名"];
        fprintf(stderr, "[tb] location denied\n");
        return;
    }

    self.busy = YES;
    [self publishStatus:@"正在定位…"];
    [self.lm startUpdatingLocation];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus st = manager.authorizationStatus;
    fprintf(stderr, "[tb] location auth = %d\n", (int)st);
    if (st == kCLAuthorizationStatusAuthorizedAlways ||
        st == kCLAuthorizationStatusAuthorized) {
        if (self.busy) [manager startUpdatingLocation];
    } else if (st == kCLAuthorizationStatusDenied || st == kCLAuthorizationStatusRestricted) {
        self.busy = NO;
        [self publishStatus:@"定位被拒绝，请在设置里填城市名"];
    }
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (!loc) return;
    [manager stopUpdatingLocation];
    self.busy = NO;

    CLLocationCoordinate2D c = loc.coordinate;
    fprintf(stderr, "[tb] located %.4f,%.4f\n", c.latitude, c.longitude);

    // 顺手反查城市名，只为了界面好看
    [[CLGeocoder new] reverseGeocodeLocation:loc
                           completionHandler:^(NSArray<CLPlacemark *> *marks, NSError *err) {
        NSString *name = marks.firstObject.locality ?: marks.firstObject.administrativeArea;
        if (name.length) {
            self.placeName = name;
            // 关键：把城市名记下来。以后刷新直接查城市，不再走定位，
            // 也就不会再弹授权框（反复 build 换签名会导致系统重新问）
            [[TBSettings shared] rememberWeatherCity:name];
        }
        [self fetchForecastAtLat:c.latitude lon:c.longitude];
    }];
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [manager stopUpdatingLocation];
    self.busy = NO;
    fprintf(stderr, "[tb] locate failed: %s\n", error.localizedDescription.UTF8String);
    [self publishStatus:[NSString stringWithFormat:@"定位失败（%@）", error.localizedDescription ?: @"未知"]];
}

#pragma mark - 城市名 → 坐标

- (void)fetchByCity:(NSString *)city {
    self.busy = YES;
    [self publishStatus:[NSString stringWithFormat:@"正在查「%@」…", city]];

    NSString *esc = [city stringByAddingPercentEncodingWithAllowedCharacters:
                     [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *url = [NSString stringWithFormat:@"%@?name=%@&count=1&language=zh&format=json",
                     kGeoSearchURL, esc];

    [self GET:url completion:^(NSDictionary *json, NSError *err) {
        if (err) {
            self.busy = NO;
            [self noteFailure:[NSString stringWithFormat:@"网络连不上（%@）",
                               err.localizedDescription ?: @"未知错误"]];
            return;
        }
        NSDictionary *hit = [json[@"results"] firstObject];
        if (!hit) {
            self.busy = NO;
            [self noteFailure:[NSString stringWithFormat:@"找不到「%@」", city]];
            return;
        }
        double lat = [hit[@"latitude"] doubleValue];
        double lon = [hit[@"longitude"] doubleValue];
        self.placeName = hit[@"name"] ?: city;
        fprintf(stderr, "[tb] geocoded %s -> %.4f,%.4f\n", city.UTF8String, lat, lon);
        [self fetchForecastAtLat:lat lon:lon];
    }];
}

/// 失败时：已经拿到过天气就保留上次的信息，别让界面变成一句错误；
/// 然后按 30s / 60s / 120s 退避重试——这台机器直连 Open-Meteo 偶发 SSL 失败，
/// 等 15 分钟的定时器太久了。
- (void)noteFailure:(NSString *)msg {
    fprintf(stderr, "[tb] %s\n", msg.UTF8String);
    if (!self.weatherKnown) [self publishStatus:@"网络连不上，稍后自动重试"];

    if (self.retryCount >= 3) { self.retryCount = 0; return; }
    NSTimeInterval delay = 30.0 * (1 << self.retryCount);
    self.retryCount++;

    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [ws refresh];
    });
}

#pragma mark - 天气

- (void)fetchForecastAtLat:(double)lat lon:(double)lon {
    NSString *url = [NSString stringWithFormat:
                     @"%@?latitude=%.4f&longitude=%.4f"
                     "&current=weather_code,wind_speed_10m,temperature_2m,cloud_cover,shortwave_radiation"
                     "&hourly=shortwave_radiation&forecast_days=1"
                     "&wind_speed_unit=ms&timezone=auto", kForecastURL, lat, lon];

    [self GET:url completion:^(NSDictionary *json, NSError *err) {
        self.busy = NO;
        NSDictionary *cur = json[@"current"];
        if (err || !cur) {
            [self noteFailure:[NSString stringWithFormat:@"天气获取失败（%@）",
                               err.localizedDescription ?: @"无数据"]];
            return;
        }

        int code = [cur[@"weather_code"] intValue];
        double wind = [cur[@"wind_speed_10m"] doubleValue];
        double temp = [cur[@"temperature_2m"] doubleValue];
        double cloud = [cur[@"cloud_cover"] doubleValue];
        double nowRad = [cur[@"shortwave_radiation"] doubleValue];
        double dayRad = TBDaylightRadiation(json[@"hourly"]);

        // 辐射接近 0 就是天黑，这时候只看云量
        BOOL night = (nowRad <= 1.0);

        TBSkyGrade grade = TBGradeFor(cloud, dayRad, night);
        TBWeather w = TBWeatherFromWMO(code, wind, cloud, dayRad, night);

        NSDateFormatter *df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm";
        NSString *when = [df stringFromDate:[NSDate date]];

        self.weather = w;
        self.weatherKnown = YES;
        self.retryCount = 0;
        [self publishStatus:[NSString stringWithFormat:@"%@ · %@（%@）%.0f°C · %@ 更新",
                             self.placeName ?: @"当前位置", TBDescribeWMO(code),
                             TBGradeName(grade), temp, when]];
        fprintf(stderr, "[tb] weather %s (code=%d wind=%.1f temp=%.0f cloud=%.0f dayRad=%.0f night=%d grade=%s)\n",
                [TBSettings slugForWeather:w].UTF8String, code, wind, temp,
                cloud, dayRad, (int)night, TBGradeName(grade).UTF8String);

        [TBSettings shared].weather = w;   // 会发通知，界面跟着换
        if (self.handler) self.handler();
    }];
}

#pragma mark - 小工具

- (void)publishStatus:(NSString *)text {
    self.status = text;
    if (self.handler) self.handler();
}

- (void)GET:(NSString *)urlString completion:(void (^)(NSDictionary *, NSError *))done {
    NSURL *u = [NSURL URLWithString:urlString];
    if (!u) { done(nil, [NSError errorWithDomain:@"tb" code:1 userInfo:nil]); return; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:u];
    req.timeoutInterval = 10;
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    NSURLSessionDataTask *task =
        [[NSURLSession sharedSession] dataTaskWithRequest:req
                                        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err) { dispatch_async(dispatch_get_main_queue(), ^{ done(nil, err); }); return; }
        NSError *jerr = nil;
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jerr] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            done([json isKindOfClass:[NSDictionary class]] ? json : nil, jerr);
        });
    }];
    [task resume];
}

@end
