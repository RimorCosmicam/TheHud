import Foundation

// hudtests — the input engine, checked without a device, a simulator or Xcode.

print("TheHud engine tests")

runFilterTests()
runAccelerationTests()
runImpulseTests()
runMomentumTests()
runRailTests()
runGestureTests()
runLayoutTests()
runHomePageTests()

exit(TestKit.summarise())
