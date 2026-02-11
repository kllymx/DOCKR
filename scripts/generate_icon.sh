#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
ICONSET_DIR="$TMP_DIR/DOCKR.iconset"
BASE_PNG="$TMP_DIR/base.png"
GEN_SRC="$TMP_DIR/gen_icon.m"

mkdir -p "$ICONSET_DIR"

cat > "$GEN_SRC" <<'SRC'
#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    if (argc < 3) {
      fprintf(stderr, "usage: gen_icon <output.png> <size>\n");
      return 1;
    }

    NSString *outputPath = [NSString stringWithUTF8String:argv[1]];
    CGFloat size = (CGFloat)atof(argv[2]);

    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];

    [[NSColor colorWithCalibratedRed:0.06 green:0.07 blue:0.10 alpha:1.0] setFill];
    NSBezierPath *bg = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0, 0, size, size)
                                                       xRadius:size * 0.22
                                                       yRadius:size * 0.22];
    [bg fill];

    CGFloat bodyW = size * 0.52;
    CGFloat bodyH = size * 0.36;
    CGFloat bodyX = (size - bodyW) / 2.0;
    CGFloat bodyY = size * 0.22;

    [[NSColor colorWithCalibratedRed:0.95 green:0.97 blue:1.0 alpha:1.0] setFill];
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(bodyX, bodyY, bodyW, bodyH)
                                                         xRadius:size * 0.06
                                                         yRadius:size * 0.06];
    [body fill];

    CGFloat shackleW = bodyW * 0.58;
    CGFloat shackleH = size * 0.34;
    CGFloat shackleX = (size - shackleW) / 2.0;
    CGFloat shackleY = bodyY + bodyH - size * 0.02;

    NSBezierPath *shackle = [NSBezierPath bezierPath];
    [shackle setLineWidth:size * 0.072];
    [shackle setLineCapStyle:NSLineCapStyleRound];
    [shackle appendBezierPathWithArcWithCenter:NSMakePoint(size / 2.0, shackleY)
                                        radius:shackleW / 2.0
                                    startAngle:200
                                      endAngle:-20
                                     clockwise:NO];
    [[NSColor colorWithCalibratedRed:0.95 green:0.97 blue:1.0 alpha:1.0] setStroke];
    [shackle stroke];

    CGFloat keyholeR = size * 0.034;
    NSBezierPath *keyhole = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(size/2.0 - keyholeR,
                                                                               bodyY + bodyH * 0.47,
                                                                               keyholeR * 2.0,
                                                                               keyholeR * 2.0)];
    [[NSColor colorWithCalibratedRed:0.08 green:0.09 blue:0.13 alpha:1.0] setFill];
    [keyhole fill];

    NSBezierPath *slot = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(size/2.0 - size*0.018,
                                                                             bodyY + bodyH * 0.24,
                                                                             size*0.036,
                                                                             size*0.12)
                                                         xRadius:size*0.018
                                                         yRadius:size*0.018];
    [slot fill];

    [image unlockFocus];

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[image TIFFRepresentation]];
    NSData *pngData = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![pngData writeToFile:outputPath atomically:YES]) {
      fprintf(stderr, "failed writing png\n");
      return 1;
    }
  }

  return 0;
}
SRC

clang -fobjc-arc -framework Cocoa "$GEN_SRC" -o "$TMP_DIR/gen_icon"
"$TMP_DIR/gen_icon" "$BASE_PNG" 1024

sips -z 16 16 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$BASE_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BASE_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$BASE_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

mkdir -p "$ROOT_DIR/dockr/Resources"
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/dockr/Resources/DOCKR.icns"

echo "Generated $ROOT_DIR/dockr/Resources/DOCKR.icns"
