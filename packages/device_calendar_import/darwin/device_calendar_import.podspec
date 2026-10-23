Pod::Spec.new do |s|
  s.name             = 'device_calendar_import'
  s.version          = '0.0.1'
  s.summary          = "Reads the device's calendars (EventKit) for BetterBAC."
  s.homepage         = 'https://github.com/link-coder100788/BetterBAC'
  s.license          = { :type => 'MIT' }
  s.author           = { 'BetterBAC' => 'dev@betterbac.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.frameworks       = 'EventKit'
  s.swift_version    = '5.0'
end
