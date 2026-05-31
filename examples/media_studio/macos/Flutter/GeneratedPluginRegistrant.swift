//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import file_picker
import file_selector_macos
import gal
import image_forge
import pixel_surface
import video_player_avfoundation

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  FileSelectorPlugin.register(with: registry.registrar(forPlugin: "FileSelectorPlugin"))
  GalPlugin.register(with: registry.registrar(forPlugin: "GalPlugin"))
  RustImageCorePlugin.register(with: registry.registrar(forPlugin: "RustImageCorePlugin"))
  RustGpuTexturePlugin.register(with: registry.registrar(forPlugin: "RustGpuTexturePlugin"))
  VideoPlayerPlugin.register(with: registry.registrar(forPlugin: "VideoPlayerPlugin"))
}
