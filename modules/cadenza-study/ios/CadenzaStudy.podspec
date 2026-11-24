Pod::Spec.new do |spec|
  spec.name = 'CadenzaStudy'
  spec.version = '0.8.0'
  spec.summary = 'Cadenza study history, widgets and Live Activities'
  spec.description = 'Native services for the Cadenza study timer.'
  spec.homepage = 'https://github.com/JuJT/Cadence'
  spec.license = { :type => 'GPL-3.0' }
  spec.author = 'Cadenza contributors'
  spec.source = { :git => 'https://github.com/JuJT/Cadence.git' }
  spec.platform = :ios, '17.6'
  spec.swift_version = '5.9'
  spec.static_framework = true
  spec.source_files = '*.swift'
  spec.frameworks = 'ActivityKit', 'WidgetKit'
  spec.dependency 'ExpoModulesCore'
end
