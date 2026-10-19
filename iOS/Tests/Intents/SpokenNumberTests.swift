import Foundation
import Testing
@testable import TimeCard

@Suite("Spoken numbers")
struct SpokenNumberTests {
    @Test func digitsAndWords() {
        #expect(SpokenNumber.parse("14") == 14)
        #expect(SpokenNumber.parse("fourteen") == 14)
        #expect(SpokenNumber.parse("Forty") == 40)
        #expect(SpokenNumber.parse("twenty-one") == 21)
        #expect(SpokenNumber.parse("twenty one") == 21)
        #expect(SpokenNumber.parse("one hundred and two") == 102)
        #expect(SpokenNumber.parse("a hundred") == 100)
        #expect(SpokenNumber.parse("two hundred fifty") == 250)
        #expect(SpokenNumber.parse("zero") == 0)
    }

    @Test func ordinalsCount() {
        #expect(SpokenNumber.parse("first") == 1)
        #expect(SpokenNumber.parse("the third") == 3)
        #expect(SpokenNumber.parse("fourteenth") == 14)
        #expect(SpokenNumber.parse("twentieth") == 20)
        #expect(SpokenNumber.parse("twenty first") == 21)
        #expect(SpokenNumber.parse("5th") == 5)
    }

    @Test func numbersInsideWords() {
        #expect(SpokenNumber.parse("row 14") == 14)
        #expect(SpokenNumber.parse("Row fourteen.") == 14)
        #expect(SpokenNumber.numbers(in: "row 14 in block 2") == [14, 2])
        #expect(SpokenNumber.numbers(in: "block three, row twenty two") == [3, 22])
        #expect(SpokenNumber.numbers(in: "no numbers here").isEmpty)
        #expect(SpokenNumber.parse("") == nil)
        #expect(SpokenNumber.parse("north") == nil)
    }

    /// Siri sometimes writes a lone number as a word that sounds the same.
    @Test func soundAlikesOnlyWhenTheyStandAlone() {
        #expect(SpokenNumber.parse("for") == 4)
        #expect(SpokenNumber.parse("to") == 2)
        #expect(SpokenNumber.parse("too") == 2)
        #expect(SpokenNumber.parse("row for") == 4)
        #expect(SpokenNumber.parse("tree to") == 2)
        #expect(SpokenNumber.numbers(in: "go to block 3") == [3])
    }

    @Test func digitizedTextForComparingNames() {
        #expect(SpokenNumber.digitized("Block Three, row twenty-two") == "block 3 row 22")
        #expect(SpokenNumber.digitized("the North field") == "the north field")
        #expect(SpokenNumber.digitized("North 3") == "north 3")
        #expect(SpokenNumber.digitized("go to block for") == "go to block 4")
    }

    @Test func wordsForSynonyms() {
        #expect(SpokenNumber.words(3) == "three")
        #expect(SpokenNumber.words(14) == "fourteen")
        #expect(SpokenNumber.words(40) == "forty")
        #expect(SpokenNumber.words(42) == "forty-two")
        #expect(SpokenNumber.words(100) == "one hundred")
        #expect(SpokenNumber.words(215) == "two hundred fifteen")
        for n in [0, 1, 9, 12, 19, 20, 33, 99, 101, 300] {
            #expect(SpokenNumber.parse(SpokenNumber.words(n)) == n, "\(n)")
        }
    }
}
