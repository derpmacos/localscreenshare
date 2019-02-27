//
// https://github.com/avaidyam/QuartzInternal/blob/master/CoreAnimationPrivate/CAPluginLayer.h
//
// Available from at least 10.9.5 - 10.14
//

@interface CAPluginLayer : CALayer

/* See `-[CALayer contentsGravity]`. The same values are accepted. */
@property (copy) NSString *pluginGravity;

/* The plugin type-dependent plugin flags. See below for available types. */
@property uint32_t pluginFlags;

/* The plugin type-depdent plugin id. See below for available types. */
@property uint64_t pluginId;

/* The WindowServer plugin to apply. See below for available types. */
@property (copy) NSString *pluginType;

@end

/** Plugin layer types (macOS only). **/

/* Currently the only supported plugin type, on macOS. Mirrors a CGSWindow into
 * the contents of the layer, if layers are hosted in the WindowServer.
 *
 * The mirrored window contents are not visible to the host application.
 *
 * `pluginId`: the CGSWindowID to mirror into the layer contents.
 * `pluginFlags`: (1 << 2): remove the window shadow when mirroring. */
static NSString *kCAPluginLayerTypeCGSWindow = @"com.apple.WindowServer.CGSWindow";
