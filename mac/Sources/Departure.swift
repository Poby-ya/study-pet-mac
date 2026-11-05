import Foundation
enum Departure {
 static func ease(_ t: Double) -> Double {let t=max(0,min(1,t));return t*t*(3-2*t)}
 static func bag(_ t: Double) -> (Double,Double) {let lift=ease((t-2)/3),carry=ease((t-10)/2);return (42-11*lift-23*carry,28-11*lift+5*carry)}
 static func item(_ t: Double) -> (Double,Double) {let lift=ease((t-4)/3),drop=ease((t-7)/3);return (19+13*lift,24-16*lift+11*drop)}
 static func signLift(_ t: Double) -> Double {-7*(1-ease((t-18)/4))}
 static func walk(_ tick: Double) -> Double {let t=max(0,min(1,(tick-18)/8));return t*t*(2-t)}
 static func pose(_ t: Double) -> Sprites.Pose {t<2 ? .restHands : t<5 ? .bend : t<10 ? .pickUp : t<16 ? .stand : t<18 ? (Int(t)%2==0 ? .waveA : .waveB) : .empty}
}
