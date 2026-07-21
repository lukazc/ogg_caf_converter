#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ogg_caf_converter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ogg_caf_converter'
  s.version          = '0.2.0'
  s.summary          = 'OGG↔CAF converter with iOS Opus decode-verified CAF repair.'
  s.description      = <<-DESC
A Flutter plugin that converts OPUS audio between OGG and CAF container
formats, and repairs crashed AVAudioRecorder CAF files using iOS
AVAudioConverter for Opus decode verification.
                       DESC
  s.homepage         = 'https://github.com/jt274/ogg_caf_converter'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Name' => 'your-email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency       'Flutter'
  s.platform         = :ios, '12.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
