require "yaml"

pubspec = YAML.load_file(File.join(__dir__, "..", "pubspec.yaml"))

# The iOS side of the graine_inapp plugin: its calls channels (Classes/GraineInAppPlugin.swift
# and the launch hook in Classes/GraineInAppLaunch.m), compiled together with Graine's iOS SDK,
# which the package carries in Classes/GraineInApp.
Pod::Spec.new do |s|
  s.name          = "graine_inapp"
  s.version       = pubspec["version"]
  s.summary       = "Graine's in-app voice agent for Flutter, with calls like WhatsApp on CallKit and VoIP pushes."
  s.description   = pubspec["description"]
  s.homepage      = pubspec["homepage"] || "https://www.graine.ai"
  s.license       = { :file => "../LICENSE" }
  s.author        = "Graine"
  s.source        = { :path => "." }

  s.platform      = :ios, "15.0"
  s.swift_version = "5.9"
  s.source_files  = "Classes/**/*.{h,m,swift}"
  # The SDK's privacy manifest: the required-reason APIs it calls, for the app's privacy report.
  s.resource_bundles = { "graine_inapp_privacy" => ["Classes/GraineInApp/PrivacyInfo.xcprivacy"] }
  s.frameworks    = "AVFoundation", "CallKit", "Combine", "CoreGraphics", "CoreText", "PushKit", "SwiftUI", "UIKit", "WebKit"
  s.dependency "Flutter"
  # As Flutter's own plugin template: a module for the Swift, and no 32-bit simulator.
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES", "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386" }
end
