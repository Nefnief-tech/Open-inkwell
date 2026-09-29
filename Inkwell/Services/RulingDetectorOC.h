#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// OpenCV-powered horizontal ruling line detection for paper photos.
@interface RulingDetectorOC : NSObject
/// Returns detected line y-positions in image point coordinates
/// (top-origin, sorted ascending). Empty array = nothing found.
+ (NSArray<NSNumber *> *)detectRulingLinesInImage:(UIImage *)image;
@end

NS_ASSUME_NONNULL_END
