require "yaml"

pubspec = YAML.load_file(File.join(__dir__, "..", "pubspec.yaml"))

# WebRTC for the calls, opt-in (README → Calls like WhatsApp → WebRTC calls):
# `ENV["GRAINE_WEBRTC"] = "1"` at the top of the app's ios/Podfile (or
# GRAINE_WEBRTC=1 in the environment of `pod install`). Off, none of it is
# compiled or downloaded.
webrtc = %w[1 true yes on].include?(ENV.fetch("GRAINE_WEBRTC", "").strip.downcase)
if webrtc && !Dir.exist?(File.join(__dir__, "GraineInAppRTC"))
  raise "GRAINE_WEBRTC is on, but this copy of graine_inapp has no ios/GraineInAppRTC"
end

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
  # With WebRTC on, the SDK's WebRTC module (GraineInAppRTC, beside Classes) is compiled into
  # this same module, and the calls find it by themselves.
  s.source_files  = ["Classes/**/*.{h,m,swift}"] + (webrtc ? ["GraineInAppRTC/**/*.swift"] : [])
  # The SDK's privacy manifest: the required-reason APIs it calls, for the app's privacy report.
  # It declares everything the WebRTC module uses too (checked when the copy is made).
  s.resource_bundles = { "graine_inapp_privacy" => ["Classes/GraineInApp/PrivacyInfo.xcprivacy"] }
  # CryptoKit and DeviceCheck: App Attest's proofs ("Require a verified app"); Security: the Keychain.
  s.frameworks    = ["AVFoundation", "CallKit", "Combine", "CoreGraphics", "CoreText", "CryptoKit", "DeviceCheck", "PushKit",
                     "Security", "SwiftUI", "UIKit", "WebKit"]
  s.dependency "Flutter"
  # A prebuilt, symbol-prefixed build of Google's libwebrtc, pinned exactly as the iOS SDK pins it.
  s.dependency "LiveKitWebRTC", "150.7871.03" if webrtc
  # As Flutter's own plugin template: a module for the Swift, and no 32-bit simulator.
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES", "EXCLUDED_ARCHS[sdk=iphonesimulator*]" => "i386" }
end
