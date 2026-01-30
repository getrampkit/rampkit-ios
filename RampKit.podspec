Pod::Spec.new do |s|
  s.name             = 'RampKit'
  s.version          = '0.0.1'
  s.summary          = 'The iOS SDK for RampKit. Build, test, and personalize app onboardings with instant updates.'
  
  s.description      = <<-DESC
RampKit enables dynamic, remotely-configurable onboarding flows that update without app releases.
The SDK fetches onboarding configurations from a CDN, renders them using native WKWebView components,
and provides rich bi-directional communication between the native host and web content.

Features:
- Dynamic onboarding flows that update without app releases
- Multi-screen navigation with smooth animations
- Rich native integrations (haptics, in-app review, notifications)
- Shared state management across screens
- Security hardening (prevents selection, zoom, copy/paste)
- Cryptographically secure user IDs stored in Keychain
- Performance optimized with preloading and caching
- Never crashes - graceful error handling throughout
                       DESC

  s.homepage         = 'https://rampkit.com'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'RampKit' => 'support@rampkit.com' }
  s.source           = { :git => 'https://github.com/getrampkit/rampkit-ios.git', :tag => s.version.to_s }
  
  s.ios.deployment_target = '14.0'
  s.swift_version = '5.9'
  
  s.source_files = 'Sources/RampKit/**/*.swift'
  
  s.frameworks = 'UIKit', 'WebKit', 'Security', 'UserNotifications', 'StoreKit'
  
  s.pod_target_xcconfig = {
    'SWIFT_VERSION' => '5.9'
  }
end







