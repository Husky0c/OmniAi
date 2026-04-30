//
//  Learn.swift
//  OmniAi
//
//  Created by 张益龙 on 2026/4/27.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack{
            Text("Hello World~")
                .font(.title)
            Image(systemName: "globe")
            HStack{
                pegs(colors: [.yellow,.cyan,.blue,.red])
            }
            HStack{
                pegs(colors: [Color.red,.green,Color.orange,Color.cyan])
            }

        }
        
    }
    
    func pegs(colors: Array<Color>) -> some View{
        HStack{
            MatchMarkers(matches: [.exact,.nomatch,.inexact,.inexact])
            
            ForEach(colors.indices, id: \.self){index in
                Circle().foregroundStyle(colors[index])
            }
        }
    }
    
}

enum Match{
    case nomatch
    case exact
    case inexact
}

struct MatchMarkers: View {
    var matches: [Match]
    
    var body: some View {
        VStack{
            HStack{
                matchMarker(peg: 0)
                matchMarker(peg: 1)
            }
            HStack{
                matchMarker(peg: 2)
                matchMarker(peg: 3)
            }
        }
    }
    
    func matchMarker(peg: Int) -> some View{
        let exactCount: Int = matches.count(where: {match in match == .exact})
        let foundCount: Int = matches.count(where: {match in match != .nomatch})
        return Circle()
            .fill(exactCount > peg ? .primary : Color.clear)
            .strokeBorder(foundCount > peg ? .primary : Color.clear, lineWidth:1)
            .aspectRatio(1, contentMode: .fit)
    }
    
}




#Preview {
    ContentView()
}
