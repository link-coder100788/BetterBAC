Pod::Spec.new do |s|
  s.name             = 'apple_coach'
  s.version          = '0.0.1'
  s.summary          = "Apple Intelligence bridge for BetterBAC's reflection coach."
  s.homepage         = 'https://github.com/betterbac'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'BetterBAC' => 'dev@betterbac.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  # Only present on iOS / macOS 26+; weak-link so older systems still launch.
  s.weak_frameworks  = 'FoundationModels'
  s.swift_version    = '5.0'
end
