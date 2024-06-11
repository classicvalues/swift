// RUN: %target-swift-frontend -enable-experimental-static-assert -emit-sil %s -verify
// REQUIRES: asserts
// REQUIRES: swift_in_compiler

//===----------------------------------------------------------------------===//
// Basic function calls and control flow
//===----------------------------------------------------------------------===//

func isOne(_ x: Int) -> Bool {
  return x == 1
}

func test_assertionSuccess() {
  #assert(isOne(1))
  #assert(isOne(1), "1 is not 1")
}

func test_assertionFailure() {
  #assert(isOne(2)) // expected-error{{assertion failed}}
  #assert(isOne(2), "2 is not 1") // expected-error{{2 is not 1}}
}

func test_nonConstant() {
  #assert(isOne(Int(readLine()!)!)) // expected-error{{#assert condition not constant}}
    // expected-note@-1 {{encountered call to 'isOne(_:)' where the 1st argument is not a constant}}
  #assert(isOne(Int(readLine()!)!), "input is not 1") // expected-error{{#assert condition not constant}}
    // expected-note@-1 {{encountered call to 'isOne(_:)' where the 1st argument is not a constant}}
}

func loops1(a: Int) -> Int {
  var x = 42
  while x <= 42 {
    x += a
  } // expected-note {{found loop here}}
  return x
}

func loops2(a: Int) -> Int {
  var x = 42
  for i in 0 ... a {
    x += i
  }
  return x
}

func infiniteLoop() -> Int {
  // expected-note @+1 {{found loop here}}
  while true {}
  return 1
}

func test_loops() {
  // expected-error @+2 {{#assert condition not constant}}
  // expected-note @+1 {{control-flow loop found during evaluation}}
  #assert(loops1(a: 20000) > 42)

  // expected-error @+2 {{#assert condition not constant}}
  // expected-note @+1 {{encountered operation not supported by the evaluator}}
  #assert(loops2(a: 20000) > 42)

  // expected-error @+2 {{#assert condition not constant}}
  // expected-note @+1 {{control-flow loop found during evaluation}}
  #assert(infiniteLoop() == 1)
}

func conditional(_ x: Int) -> Int {
  if x < 0 {
    return 0
  } else {
    return x
  }
}

func test_conditional() {
  #assert(conditional(-5) == 0)
  #assert(conditional(5) == 5)

  // expected-error @+1 {{assertion failed}}
  #assert(conditional(-5) == 1)
  // expected-error @+1 {{assertion failed}}
  #assert(conditional(5) == 1)
}

//===----------------------------------------------------------------------===//
// Top-level evaluation
//===----------------------------------------------------------------------===//

func test_topLevelEvaluation(topLevelArgument: Int) {
  let topLevelConst = 1
  #assert(topLevelConst == 1)

  // The #assert successfully sees the value of this `var` even though it is
  // mutable because DiagnosticConstantPropagation propagates its value.
  var topLevelVar = 1 // expected-warning {{never mutated}}
  #assert(topLevelVar == 1)

  // expected-note @+1 {{cannot evaluate top-level value as constant here}}
  var topLevelVarConditionallyMutated = 1
  if topLevelVarConditionallyMutated < 0 {
    topLevelVarConditionallyMutated += 1
  }
  // expected-error @+1 {{#assert condition not constant}}
  #assert(topLevelVarConditionallyMutated == 1)

  // expected-error @+1 {{#assert condition not constant}}
  #assert(topLevelArgument == 1)
    // expected-note@-1 {{cannot evaluate expression as constant here}}
}

//===----------------------------------------------------------------------===//
// Integers
//===----------------------------------------------------------------------===//

func test_trapsAndOverflows() {
  // The error message below is generated by the traditional constant folder.
  // The interpreter responsible for #assert does not generate an overflow
  // error because the traditional constant folder replaces the condition with
  // a constant before the #assert interpreter sees it.
  // expected-error @+1 {{arithmetic operation '124 + 92' (on type 'Int8') results in an overflow}}
  #assert((124 as Int8) + 92 < 42)

  // One error message below is generated by the traditional constant folder.
  // The interpreter responsible for #assert does generate an additional error
  // message.
  // expected-error @+2 {{integer literal '123231' overflows when stored into 'Int8'}}
  // expected-error @+1 {{#assert condition not constant}}
  #assert(Int8(123231) > 42)
  // expected-note @-1 {{integer overflow detected}}

  // The error message below is generated by the traditional constant folder.
  // The interpreter responsible for #assert does not generate an overflow
  // error because the traditional constant folder replaces the condition with
  // a constant before the #assert interpreter sees it.
  // expected-error @+2 {{arithmetic operation '124 + 8' (on type 'Int8') results in an overflow}}
  // expected-error @+1 {{assertion failed}}
  #assert(Int8(124) + 8 > 42)
}

// Calling this stops the traditional mandatory constant folder from folding
// the arithmetic before ConstExpr.cpp gets it.
func identity(_ x: Int) -> Int {
  return x
}

func test_integerArithmetic() {
  #assert(identity(1) + 1 == 2)
  #assert(identity(1) - 1 == 0)
  #assert(identity(2) * 2 == 4)
  #assert(identity(10) / 10 == 1)
  #assert(identity(10) % 7 == 3)
  #assert(identity(1) < 2)
  #assert(identity(1) <= 1)
  #assert(identity(2) > 1)
  #assert(identity(1) >= 1)
}

//===----------------------------------------------------------------------===//
// Custom structs and tuples
//===----------------------------------------------------------------------===//

struct CustomStruct {
  let x: (Int, Int)
  let y: Int
}

func test_CustomStruct() {
  let cs = CustomStruct(x: (1, 2), y: 3)
  #assert(cs.x.0 == 1)
  #assert(cs.x.1 == 2)
  #assert(cs.y == 3)
}

//===----------------------------------------------------------------------===//
// Mutation
//===----------------------------------------------------------------------===//

struct InnerStruct {
  var a, b: Int
}

struct MutableStruct {
  var x: InnerStruct
  var y: Int
}

func addOne(to target: inout Int) {
  target += 1
}

func callInout() -> Bool {
  var myMs = MutableStruct(x: InnerStruct(a: 1, b: 2), y: 3)
  addOne(to: &myMs.x.a)
  addOne(to: &myMs.y)
  return (myMs.x.a + myMs.x.b + myMs.y) == 8
}

func replaceAggregate() -> Bool {
  var myMs = MutableStruct(x: InnerStruct(a: 1, b: 2), y: 3)
  myMs.x = InnerStruct(a: 10, b: 20)
  return myMs.x.a == 10 && myMs.x.b == 20 && myMs.y == 3
}

func shouldNotAlias() -> Bool {
  var x = 1
  var y = x
  x += 1
  y += 2
  return x == 2 && y == 3
}

func invokeMutationTests() {
  #assert(callInout())
  #assert(replaceAggregate())
  #assert(shouldNotAlias())
}

//===----------------------------------------------------------------------===//
// Evaluating generic functions
//===----------------------------------------------------------------------===//

func genericAdd<T: Numeric>(_ a: T, _ b: T) -> T {
  return a + b
}

func test_genericAdd() {
  #assert(genericAdd(1, 1) == 2)
}

func test_tupleAsGeneric() {
  func identity<T>(_ t: T) -> T {
    return t
  }
  #assert(identity((1, 2)) == (1, 2))
}

//===----------------------------------------------------------------------===//
// Reduced testcase propagating substitutions around.
//===----------------------------------------------------------------------===//
protocol SubstitutionsP {
  init<T: SubstitutionsP>(something: T)

  func get() -> Int
}

struct SubstitutionsX : SubstitutionsP {
  var state : Int
  init<T: SubstitutionsP>(something: T) {
    state = something.get()
  }
  func get() -> Int {
    fatalError()
  }

  func getState() -> Int {
    return state
  }
}

struct SubstitutionsY : SubstitutionsP {
  init() {}
  init<T: SubstitutionsP>(something: T) {
  }

  func get() -> Int {
    return 123
  }
}
func substitutionsF<T: SubstitutionsP>(_: T.Type) -> T {
  return T(something: SubstitutionsY())
}

func testProto() {
  #assert(substitutionsF(SubstitutionsX.self).getState() == 123)
}

//===----------------------------------------------------------------------===//
// Structs with generics
//===----------------------------------------------------------------------===//

// Test 1
struct S<X, Y> {
  func method<Z>(_ z: Z) -> Int {
    return 0
  }
}

func callerOfSMethod<U, V, W>(_ s: S<U, V>, _ w: W) -> Int {
  return s.method(w)
}

func toplevel() {
  let s = S<Int, Float>()
  #assert(callerOfSMethod(s, -1) == 0)
}

// Test 2: test a struct method returning its generic argument.
struct S2<X> {
  func method<Z>(_ z: Z) -> Z {
    return z
  }
}

func callerOfS2Method<U, V>(_ s: S2<U>, _ v: V) -> V {
  return s.method(v)
}

func testStructMethodReturningGenericParam() {
  let s = S2<Float>()
  #assert(callerOfS2Method(s, -1) == -1)
}

//===----------------------------------------------------------------------===//
// Test that the order in which the generic parameters are declared doesn't
// affect the interpreter.
//===----------------------------------------------------------------------===//

protocol Proto {
  func amethod<U>(_ u: U) -> Int
}

func callMethod<U, T: Proto>(_ a: T, _ u: U) -> Int {
  return a.amethod(u)
}

// Test 1
struct Sp : Proto {
  func amethod<U>(_ u: U) -> Int {
    return 0
  }
}

func testProtocolMethod() {
  let s = Sp()
  #assert(callMethod(s, 10) == 0)
}

// Test 2
struct GenericS<P>: Proto {
  func amethod<U>(_ u: U) -> Int {
    return 12
  }
}

func testProtocolMethodForGenericStructs() {
  let s = GenericS<Int>()
  #assert(callMethod(s, 10) == 12)
}

// Test 3 (with generic fields)
struct GenericS2<P: Equatable>: Proto {
  var fld1: P
  var fld2: P

  init(_ p: P, _ q: P) {
    fld1 = p
    fld2 = q
  }

  func amethod<U>(_ u: U) -> Int {
    if (fld1 == fld2) {
      return 15
    }
    return 0
  }
}

func testProtocolMethodForStructsWithGenericFields() {
  let s = GenericS2<Int>(1, 1)
  #assert(callMethod(s, 10) == 15)
}

//===----------------------------------------------------------------------===//
// Structs with generics and protocols with associated types.
//===----------------------------------------------------------------------===//

protocol ProtoWithAssocType {
  associatedtype U

  func amethod(_ u: U) -> U
}

struct St<X, Y> : ProtoWithAssocType {
  typealias U = X

  func amethod(_ x: X) -> X {
    return x
  }
}

func callerOfStMethod<P, Q>(_ s: St<P, Q>, _ p: P) -> P {
  return s.amethod(p)
}

func testProtoWithAssocTypes() {
  let s = St<Int, Float>()
  #assert(callerOfStMethod(s, 11) == 11)
}

// Test 2: test a protocol method returning its generic argument.
protocol ProtoWithGenericMethod {
  func amethod<U>(_ u: U) -> U
}


struct SProtoWithGenericMethod<X> : ProtoWithGenericMethod {
  func amethod<Z>(_ z: Z) -> Z {
    return z
  }
}

func callerOfGenericProtoMethod<S: ProtoWithGenericMethod, V>(_ s: S,
                                                              _ v: V) -> V {
  return s.amethod(v)
}

func testProtoWithGenericMethod() {
  let s = SProtoWithGenericMethod<Float>()
  #assert(callerOfGenericProtoMethod(s, -1) == -1)
}

//===----------------------------------------------------------------------===//
// Converting a struct instance to protocol instance is not supported yet.
// This requires handling init_existential_addr instruction. Once they are
// supported, the following static assert must pass. For now, a workaround is
// to use generic parameters with protocol constraints in the interpretable
// code fragments.
//===----------------------------------------------------------------------===//

protocol ProtoSimple {
  func amethod() -> Int
}

func callProtoSimpleMethod(_ p: ProtoSimple) -> Int {
  return p.amethod()
}

struct SPsimp : ProtoSimple {
  func amethod() -> Int {
    return 0
  }
}

func testStructPassedAsProtocols() {
  let s = SPsimp()
  #assert(callProtoSimpleMethod(s) == 0) // expected-error {{#assert condition not constant}}
    // expected-note@-1 {{encountered call to 'callProtoSimpleMethod(_:)' where the 1st argument is not a constant}}
}

//===----------------------------------------------------------------------===//
// Strings
//===----------------------------------------------------------------------===//

struct ContainsString {
  let x: Int
  let str: String
}

// Test string initialization

func stringInitEmptyTopLevel() {
  let c = ContainsString(x: 1, str: "")
  #assert(c.x == 1)
}

func stringInitNonEmptyTopLevel() {
  let c = ContainsString(x: 1, str: "hello world")
  #assert(c.x == 1)
}

// Test string equality (==)

func emptyString() -> String {
  return ""
}

func asciiString() -> String {
  return "test string"
}

func dollarSign() -> String {
  return "dollar sign: \u{24}"
}

func flag() -> String {
  return "flag: \u{1F1FA}\u{1F1F8}"
}

func compareWithIdenticalStrings() {
  #assert(emptyString() == "")
  #assert(asciiString() == "test string")
  #assert(dollarSign() == "dollar sign: $")
  #assert(flag() == "flag: 🇺🇸")
}

func compareWithUnequalStrings() {
  #assert(emptyString() == "Nonempty") // expected-error {{assertion failed}}
  #assert(asciiString() == "")         // expected-error {{assertion failed}}
  #assert(dollarSign() == flag())      // expected-error {{assertion failed}}
  #assert(flag() == "flag: \u{1F496}") // expected-error {{assertion failed}}
}

// Test string appends (+=)

// String.+= when used at the top-level of #assert cannot be folded as the
// interpreter cannot extract the relevant instructions to interpret.
// (This is because append is a mutating function and there will be more than
// one writer to the string.) Nonetheless, flow-sensitive uses of String.+=
// will be interpretable.
func testStringAppendTopLevel() {
  var a = "a"
  a += "b"
  #assert(a == "ab")  // expected-error {{#assert condition not constant}}
                      // expected-note@-1 {{operation with invalid operands encountered during evaluation}}
  // Note: the operands to the equals operation are invalid as the variable
  // `a` is uninitialized when the call is made. This is due to imprecision
  // in the top-level evaluation mode.
}

func appendedAsciiString() -> String {
  var str = "test "
  str += "string"
  return str
}

func appendedDollarSign() -> String {
  var d = "dollar sign: "
  d += "\u{24}"
  return d
}

func appendedFlag() -> String {
  var flag = "\u{1F1FA}"
  flag += "\u{1F1F8}"
  return flag
}

func testStringAppend() {
  #assert(appendedAsciiString() == asciiString())
  #assert(appendedDollarSign() == dollarSign())
  #assert(appendedFlag() == "🇺🇸")

  #assert(appendedAsciiString() == "") // expected-error {{assertion failed}}
  #assert(appendedDollarSign() == "")  // expected-error {{assertion failed}}
  #assert(appendedFlag() == "")        // expected-error {{assertion failed}}
}

func conditionalAppend(_ b: Bool, _ str1: String, _ str2: String) -> String {
  let suffix = "One"
  var result = ""
  if b {
    result = str1
    result += suffix
  } else {
    result = str2
    result += suffix
  }
  return result
}

func testConditionalAppend() {
  let first = "first"
  let second = "second"
  #assert(conditionalAppend(true, first, second) == "firstOne")
  #assert(conditionalAppend(false, first, second) == "secondOne")
}

struct ContainsMutableString {
  let x: Int
  var str: String
}

func appendOfStructProperty() -> ContainsMutableString {
  var c = ContainsMutableString(x: 0, str: "broken")
  c.str += " arrow"
  return c
}

func testAppendOfStructProperty() {
  #assert(appendOfStructProperty().str == "broken arrow")
}

//===----------------------------------------------------------------------===//
// Enums and optionals.
//===----------------------------------------------------------------------===//
func isNil(_ x: Int?) -> Bool {
  return x == nil
}

#assert(isNil(nil))
#assert(!isNil(3))

public enum Pet {
  case bird
  case cat(Int)
  case dog(Int, Int)
  case fish
}

public func weighPet(pet: Pet) -> Int {
  switch pet {
  case .bird: return 3
  case let .cat(weight): return weight
  case let .dog(w1, w2): return w1+w2
  default: return 1
  }
}

#assert(weighPet(pet: .bird) == 3)
#assert(weighPet(pet: .fish) == 1)
#assert(weighPet(pet: .cat(2)) == 2)
// expected-error @+1 {{assertion failed}}
#assert(weighPet(pet: .cat(2)) == 3)
#assert(weighPet(pet: .dog(9, 10)) == 19)

// Test indirect enums.
indirect enum IntExpr {
  case int(_ value: Int)
  case add(_ lhs: IntExpr, _ rhs: IntExpr)
  case multiply(_ lhs: IntExpr, _ rhs: IntExpr)
}

func evaluate(intExpr: IntExpr) -> Int {
  switch intExpr {
  case .int(let value):
    return value
  case .add(let lhs, let rhs):
    return evaluate(intExpr: lhs) + evaluate(intExpr: rhs)
  case .multiply(let lhs, let rhs):
    return evaluate(intExpr: lhs) * evaluate(intExpr: rhs)
  }
}

// TODO: The constant evaluator can't handle indirect enums yet.
// expected-error @+2 {{#assert condition not constant}}
// expected-note @+1 {{encountered call to 'evaluate(intExpr:)' where the 1st argument is not a constant}}
#assert(evaluate(intExpr: .int(5)) == 5)
// expected-error @+2 {{#assert condition not constant}}
// expected-note @+1 {{encountered call to 'evaluate(intExpr:)' where the 1st argument is not a constant}}
#assert(evaluate(intExpr: .add(.int(5), .int(6))) == 11)
// expected-error @+2 {{#assert condition not constant}}
// expected-note @+1 {{encountered call to 'evaluate(intExpr:)' where the 1st argument is not a constant}}
#assert(evaluate(intExpr: .add(.multiply(.int(2), .int(2)), .int(3))) == 7)

// Test address-only enums.
protocol IntContainerProtocol {
  var value: Int { get }
}

struct IntContainer : IntContainerProtocol {
  let value: Int
}

enum AddressOnlyEnum<T: IntContainerProtocol> {
  case double(_ value: T)
  case triple(_ value: T)
}

func evaluate<T>(addressOnlyEnum: AddressOnlyEnum<T>) -> Int {
  switch addressOnlyEnum {
  case .double(let value):
    return 2 * value.value
  case .triple(let value):
    return 3 * value.value
  }
}

#assert(evaluate(addressOnlyEnum: .double(IntContainer(value: 1))) == 2)
#assert(evaluate(addressOnlyEnum: .triple(IntContainer(value: 1))) == 3)

//===----------------------------------------------------------------------===//
// Arrays
//===----------------------------------------------------------------------===//

// When the const-evaluator evaluates this struct, it forces evaluation of the
// `arr` value.
struct ContainsArray {
  let x: Int
  let arr: [Int]
}

func arrayInitEmptyTopLevel() {
  let c = ContainsArray(x: 1, arr: Array())
  #assert(c.x == 1)
}

func arrayInitEmptyLiteralTopLevel() {
  // TODO: More work necessary for array initialization using literals to work
  // at the top level.
  // expected-note@+1 {{encountered call to 'ContainsArray.init(x:arr:)' where the 2nd argument is not a constant}}
  let c = ContainsArray(x: 1, arr: [])
  // expected-error @+1 {{#assert condition not constant}}
  #assert(c.x == 1)
}

func arrayInitLiteral() {
  // TODO: More work necessary for array initialization using literals to work
  // at the top level.
  // expected-note @+1 {{encountered call to 'ContainsArray.init(x:arr:)' where the 2nd argument is not a constant}}
  let c = ContainsArray(x: 1, arr: [2, 3, 4])
  // expected-error @+1 {{#assert condition not constant}}
  #assert(c.x == 1)
}

func arrayInitNonConstantElementTopLevel(x: Int) {
  // expected-note @+1 {{encountered call to 'ContainsArray.init(x:arr:)' where the 2nd argument is not a constant}}
  let c = ContainsArray(x: 1, arr: [x])
  // expected-error @+1 {{#assert condition not constant}}
  #assert(c.x == 1)
}

func arrayInitEmptyFlowSensitive() -> ContainsArray {
  return ContainsArray(x: 1, arr: Array())
}

func invokeArrayInitEmptyFlowSensitive() {
  #assert(arrayInitEmptyFlowSensitive().x == 1)
}

func arrayInitEmptyLiteralFlowSensitive() -> ContainsArray {
  return ContainsArray(x: 1, arr: [])
}

func invokeArrayInitEmptyLiteralFlowSensitive() {
  #assert(arrayInitEmptyLiteralFlowSensitive().x == 1)
}

func arrayInitLiteralFlowSensitive() -> ContainsArray {
  return ContainsArray(x: 1, arr: [2, 3, 4])
}

func invokeArrayInitLiteralFlowSensitive() {
  #assert(arrayInitLiteralFlowSensitive().x == 1)
}
