Pod::Spec.new do |s|
  s.name             = 'live_activity'
  s.version          = '0.0.1'
  s.summary          = "BetterBAC's streak Live Activity (ActivityKit)."
  s.homepage         = 'https://github.com/link-coder100788/BetterBAC'
  s.license          = { :type => 'MIT' }
  s.author           = { 'BetterBAC' => 'dev@betterbac.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  # ActivityKit exists on iOS 16.1+; weak-link so older iOS still launches.
  s.weak_frameworks  = 'ActivityKit'
  s.swift_version    = '5.0'
end
