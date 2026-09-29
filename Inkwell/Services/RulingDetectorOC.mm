#import "RulingDetectorOC.h"

#import <opencv2/core.hpp>
#import <opencv2/imgproc.hpp>

#import <cmath>

@implementation RulingDetectorOC

+ (NSArray<NSNumber *> *)detectRulingLinesInImage:(UIImage *)image {
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return @[];

    const int srcW = (int)CGImageGetWidth(cgImage);
    const int srcH = (int)CGImageGetHeight(cgImage);
    if (srcW < 60 || srcH < 60) return @[];

    // Work at ~960 px width.
    const double scale = 960.0 / (double)srcW;
    const int w = 960;
    const int h = MAX(2, (int)round(srcH * scale));
    if (h < 40) return @[];

    std::vector<uchar> buffer((size_t)w * (size_t)h, 0);
    CGContextRef ctx = CGBitmapContextCreate(buffer.data(), w, h, 8, w,
                                             CGColorSpaceCreateDeviceGray(),
                                             kCGImageAlphaNone);
    if (!ctx) return @[];
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cgImage);
    CGContextRelease(ctx);

    cv::Mat gray(h, w, CV_8UC1, buffer.data());
    cv::GaussianBlur(gray, gray, cv::Size(3, 3), 0);

    // Probabilistic Hough: ruling lines are long, near-horizontal runs.
    std::vector<cv::Vec4i> segments;
    const double minLineLength = 0.30 * (double)w;
    cv::HoughLinesP(gray, segments, 1.0, CV_PI / 180.0, 70, minLineLength, 14);
    if (segments.empty()) {
        cv::HoughLinesP(gray, segments, 1.0, CV_PI / 180.0, 40,
                        minLineLength * 0.7, 20);
    }

    // Keep near-horizontal segments (|dy| <= 0.15 |dx|).
    std::vector<double> ys;
    for (const auto &l : segments) {
        const double dx = std::abs((double)(l[2] - l[0]));
        const double dy = std::abs((double)(l[3] - l[1]));
        if (dx < 4.0 || dy > 0.15 * dx) continue;
        ys.push_back(((double)l[1] + (double)l[3]) / 2.0);
    }
    if (ys.size() < 2) return @[];
    std::sort(ys.begin(), ys.end());

    // Cluster consecutive candidate ys within 8 px.
    std::vector<double> clustered;
    double sum = ys[0];
    int count = 1;
    for (size_t i = 1; i < ys.size(); ++i) {
        if (ys[i] - ys[i - 1] <= 8.0) {
            sum += ys[i];
            count++;
        } else {
            clustered.push_back(sum / count);
            sum = ys[i];
            count = 1;
        }
    }
    clustered.push_back(sum / count);
    if (clustered.size() < 2 || clustered.size() > 200) return @[];

    // Bitmap row 0 is the image BOTTOM (CG y-up) → convert to top-origin
    // page points (source pixels are points at scale 1).
    const double pxToPoint = 1.0 / scale;
    NSMutableArray<NSNumber *> *result = [NSMutableArray array];
    for (double rowY : clustered) {
        [result addObject:@(((double)h - rowY) * pxToPoint)];
    }
    return result;
}

@end
