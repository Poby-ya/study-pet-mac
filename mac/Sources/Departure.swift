import Foundation
enum Departure {
 static func ease(_ t: Double) -> Double {let t=max(0,min(1,t));return t*t*(3-2*t)}
 static func bag(_ t: Double) -> (Double,Double) {let lift=ease(t/4),carry=ease((t-10)/2);return (50-16*lift-24*carry,28-11*lift+5*carry)}
 static func item(_ t: Double) -> (Double,Double) {let lift=ease((t-4)/3),drop=ease((t-7)/3);return (19+16*lift,24-12*lift+7*drop)}
 static func signLift(_ t: Double) -> Double {7*(1-ease((t-12)/4))}
 static func hand(_ t: Double) -> (Double,Double) {let b=bag(t),p=item(t),mix=ease(t-3)*(1-ease(t-9));return (b.0+(p.0-b.0)*mix+3,b.1+(p.1-b.1)*mix+1)}
 static func walk(_ tick: Double) -> Double {let t=max(0,min(1,(tick-18)/8));return t*t*(2-t)}
 static func pose(_ t: Double) -> Sprites.Pose {t<16 ? .pack : t<18 ? (Int(t)%2==0 ? .waveA : .waveB) : .empty}
}
