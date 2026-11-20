import Foundation
enum Departure {
 static func ease(_ t: Double) -> Double {let t=max(0,min(1,t));return t*t*(3-2*t)}
 /// Up from its hook onto the desk, packed, and hung back by tick 12: the app stays on, so the bag stays
 /// and its owner walks out empty-handed (user, 2026-11-20). Windows: Departure.Bag.
 static func bag(_ t: Double) -> (Double,Double) {let up=ease(t/4)*(1-ease((t-10)/2));return (50-14*up,28-11*up)}
 static func item(_ t: Double,_ laptop: Bool=false) -> (Double,Double) {let lift=ease((t-4)/3),drop=ease((t-7)/3);return ((laptop ? 23.0 : 24.0)+(laptop ? 14.0 : 13.0)*lift,25-13*lift+7*drop)}
 static func signLift(_ t: Double) -> Double {7*(1-ease((t-12)/4))}
 static func hand(_ t: Double,_ laptop: Bool=false) -> (Double,Double) {let b=bag(t),p=item(t,laptop),mix=ease(t-3)*(1-ease(t-9));return (b.0+(p.0-b.0)*mix+3,b.1+(p.1-b.1)*mix+1)}
 static func walk(_ tick: Double) -> Double {let t=max(0,min(1,(tick-18)/8));return t*t*(2-t)}
 // The wave keeps its left arm now no hand holds the bag.
 static func pose(_ t: Double) -> Sprites.Pose {t<2 ? .stand : t<16 ? .packR : t<18 ? (Int(t)%2==0 ? .waveA : .waveB) : .empty}
 /// Coming in to study is leaving played backwards, without the sign and the wave: two seconds'
 /// walk in empty-handed (departure ticks 26 → 18), then unpacking from the hung bag at the desk (12 → 0).
 static let arrivalTicks = 18.0
 static func arrival(_ tick: Double) -> Double {tick<8 ? 26-tick : max(0,11.9*(1-(tick-8)/10))}
}

/// A friend's trip across the room, in ticks: up from their seat and over, a visit, then back.
enum Travel {
 static let total = 24.0, arrive = 5.0, leave = 19.0
 static func walking(_ tick: Double) -> Bool {tick<arrive || tick>leave}
 static func progress(_ tick: Double) -> Double {let t=tick<0 ? 0 : tick<arrive ? tick/arrive : tick<=leave ? 1 : max(0,(total-tick)/(total-leave));return t*t*(3-2*t)}
 /// 1 still seated, 0 on their feet: they rise before setting off and sit when they get back.
 static func seated(_ tick: Double) -> Double {tick<1 ? 1-Departure.ease(tick) : tick>total-1 ? Departure.ease(tick-(total-1)) : 0}
}
