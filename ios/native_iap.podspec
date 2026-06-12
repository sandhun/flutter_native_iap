Pod::Spec.new do |s|
  s.name             = 'native_iap'
  s.version          = '1.0.0'
  s.summary          = 'Native in-app purchase plugin (StoreKit / BillingClient) via method channel'
  s.description      = 'Reusable in-app purchase library using native StoreKit (iOS) and BillingClient (Android) via method channels.'
  s.homepage         = 'https://github.com/sandhun/flutter_native_iap'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sandhun Senavirathna' => 'sandhun.emedia@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.swift_version = '5.0'
end
