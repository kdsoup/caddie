
signature AST = sig

  datatype 'i exp = Real of real * 'i
                  | Zero of 'i
                  | Let of string * 'i exp * 'i exp * 'i
                  | Add of 'i exp * 'i exp * 'i
                  | Sub of 'i exp * 'i exp * 'i
                  | Mul of 'i exp * 'i exp * 'i
                  | Var of string * 'i
                  | App of string * 'i exp * 'i
                  | Tuple of 'i exp list * 'i
                  | Prj of int * 'i exp * 'i
                  | Map of string * 'i exp * 'i exp * 'i
                  | Iota of int * 'i
                  | Pow of real * 'i exp * 'i

  val pr_exp      : 'i exp -> string
  val info_of_exp : 'i exp -> 'i

  type v
  val pr_v : v -> string
  val real_v : real -> v

  type 'a env
  val look    : 'a env -> string -> 'a option
  val insert  : 'a env -> string * 'a -> 'a env
  val plus    : 'a env * 'a env -> 'a env

  val VEinit  : v env
  val VEempty : v env
  val eval    : ('i -> Region.reg) -> v env -> 'i exp -> v

  val parse   : {srcname:string,input:string} -> Region.reg exp

  type 'i prg = (string * string * 'i exp * 'i) list

  val pr_prg    : 'i prg -> string
  val eval_prg  : ('i -> Region.reg) -> 'i prg -> string -> v -> v
  val eval_exp  : ('i -> Region.reg) -> 'i prg -> 'i exp -> v
  val parse_prg : {srcname:string,input:string} -> Region.reg prg

  type ty
  val real_ty   : ty
  val tuple_ty  : ty list -> ty
  val fun_ty    : ty * ty -> ty
  val fresh_ty  : unit -> ty
  val eq_ty     : ty * ty -> bool
  val unify_ty  : Region.reg -> ty * ty -> unit           (* may raise Fail *)
  val unify_prj_ty : Region.reg -> int * ty * ty -> unit  (* (i,elemty,recordty) *)
  val pr_ty     : ty -> string

  val un_tuple  : ty -> ty list option
  val un_array  : ty -> ty option
  val un_fun    : ty -> (ty*ty)option
  val is_real   : ty -> bool

  val TEinit    : ty env
  val TEempty   : ty env
  val tyinf_exp : ty env -> Region.reg exp -> (Region.reg*ty) exp * ty
  val tyinf_prg : Region.reg prg -> (Region.reg*ty) prg * ty env
end

structure Ast :> AST = struct

fun debug_p () = false

fun dieLoc l s =
    raise Fail (Region.ppLoc l ^ ": " ^ s)

fun dieReg r s =
    raise Fail (Region.pp r ^ ": " ^ s)

structure T = SimpleToken

fun is_id s =
    size s > 0 andalso
    let val c0 = String.sub(s,0)
    in Char.isAlpha c0 orelse c0 = #"_"
    end andalso CharVector.all (fn c => Char.isAlphaNum c orelse c = #"_") s

fun string_to_real s : real option =
    let fun getC i =
            SOME(String.sub(s,i),i+1)
            handle _ => NONE
    in if CharVector.all (fn c => not(Char.isSpace c) andalso c <> #"~") s then
         case Real.scan getC 0 of
             SOME (r,i) => if i = size s then SOME r else NONE
           | NONE => NONE
       else NONE
    end

fun string_to_int s : int option =
    let fun getC i =
            SOME(String.sub(s,i),i+1)
            handle _ => NONE
    in if CharVector.all (fn c => not(Char.isSpace c) andalso c <> #"~") s then
         case Int.scan StringCvt.DEC getC 0 of
             SOME (n,i) => if i = size s then SOME n else NONE
           | NONE => NONE
       else NONE
    end

fun real_to_string r =
    CharVector.map (fn #"~" => #"-" | c => c) (Real.toString r)

fun is_num s =
    Option.isSome(string_to_real s) orelse
    (size s > 0 andalso String.sub(s,size s - 1) = #"." andalso
     Option.isSome(string_to_int(String.substring(s,0,size s -1))))

fun tokens {srcname,input} =
    T.tokenise {sep_chars="(){}[],;",
                symb_chars="#&|+-~^?*:!%/='<>@",
                is_id=is_id,
                is_num=is_num}
               {srcname=srcname,input=input}

fun prTokens ts =
    ( print ("Tokens:\n")
    ; app (fn (t,r) => print (Region.pp r ^ ":" ^ T.pp_token t ^ ", ")) ts
    ; print "\n\n"
    )

fun lexing {srcname,input} =
    let val ts = tokens {srcname=srcname,input=input}
    in if debug_p() then prTokens ts else ()
     ; ts
    end

structure P = Parse(type token = T.token
                    val pp_token = T.pp_token)

open P

datatype 'i exp = Real of real * 'i
                | Zero of 'i
                | Let of string * 'i exp * 'i exp * 'i
                | Add of 'i exp * 'i exp * 'i
                | Sub of 'i exp * 'i exp * 'i
                | Mul of 'i exp * 'i exp * 'i
                | Var of string * 'i
                | App of string * 'i exp * 'i
                | Tuple of 'i exp list * 'i
                | Prj of int * 'i exp * 'i
                | Map of string * 'i exp * 'i exp * 'i
                | Iota of int * 'i
                | Pow of real * 'i exp * 'i

fun par p x s =
    if x > p then s else "(" ^ s ^ ")"

fun pr_exp (e: 'i exp) : string =
    let fun pr (p:int) (e: 'i exp) : string =
            case e of
                Real (r,_) =>
                let val s = real_to_string r
                in if p = 9 then " " ^ s else s
                end
              | Zero r =>  if p = 9 then " 0" else "0"
              | Let (x,e1,e2,_) => "let " ^ x ^ " = " ^ pr 0 e1 ^ " in " ^ pr 0 e2 ^ " end"
              | Add (e1,e2,_) => par p 6 (pr 6 e1 ^ "+" ^ pr 6 e2)
              | Sub (e1,e2,_) => par p 6 (pr 6 e1 ^ "-" ^ pr 6 e2)
              | Mul (e1,e2,_) => par p 7 (pr 7 e1 ^ "*" ^ pr 7 e2)
              | Var (x,_) => if p = 9 then " " ^ x else x
              | App (f,e,_) => par p 8 (f ^ pr 9 e)
              | Tuple (es,_) => "(" ^ String.concatWith "," (map (pr 0) es) ^ ")"
              | Prj (i,e,_) => "#" ^ Int.toString i ^ " " ^ par p 8 (pr 8 e)
	      | Map (x,f,es,_) => "map (fn " ^ x ^ " => " ^ pr_exp f ^ ") " ^ pr_exp es
	      | Iota (n,_)  => "iota " ^ Int.toString n
              | Pow (r,e,_) => "pow " ^ real_to_string r ^ " " ^ par p 8 (pr 8 e)
    in pr 0 e
    end

datatype v = Real_v of real | Fun_v of v -> v | Tuple_v of v list | Array_v of v list | Zero_v

fun real_v r = Real_v r

type 'a env = (string * 'a)list

fun pr_v (Real_v r) = real_to_string r
  | pr_v Zero_v = "0"
  | pr_v (Fun_v _) = "fn"
  | pr_v (Tuple_v vs) = "(" ^ String.concatWith "," (map pr_v vs) ^ ")"
  | pr_v (Array_v vs) = "[" ^ String.concatWith "," (map pr_v vs) ^ "]"

fun toReal s (v:v) : real =
    case v of
        Real_v r => r
      | Zero_v => 0.0
      | _ => raise Fail ("eval: " ^ s ^ " expecting real")

fun lift1r s (opr : real -> real) : string * v =
    (s, Fun_v(fn v => Real_v(opr (toReal s v))))

fun lift_rxr_r s (opr : real * real -> real) : string * v =
    (s, Fun_v(fn (Tuple_v[v1,v2]) =>
                 let val r1 = toReal s v1
                     val r2 = toReal s v2
                     val r' = opr (r1,r2)
                 in Real_v r'
                 end
               | Zero_v => Zero_v  (* works for norm2sq *)
               | _ => raise Fail ("eval: " ^ s ^ " expects a pair of reals as argument")))

fun lift_rNxrN_r s (opr : real list * real list -> real) : string * v =
    (s, Fun_v(fn (Tuple_v[Array_v vs1,Array_v vs2]) =>
                 let val rs1 = map (toReal s) vs1
                     val rs2 = map (toReal s) vs2
                 in Real_v(opr (rs1,rs2))
                 end
               | _ => raise Fail ("eval: " ^ s ^ " expects a pair of real arrays as argument")))

fun lift_rxrN_rN s (opr : real * real list -> real list) : string * v =
    (s, Fun_v(fn (Tuple_v[v,Array_v vs]) =>
                 let val r = toReal s v
                     val rs = map (toReal s) vs
                     val rs' = opr (r,rs)
                     val vs' = map Real_v rs'
                 in Array_v vs'
                 end
               | _ => raise Fail ("eval: " ^ s ^ " expects a pair of real and a real array as argument")))

fun lift_r3xr3_r3 s (opr : (real*real*real) * (real*real*real) -> (real*real*real)) : string * v =
    (s, Fun_v(fn (Tuple_v[Tuple_v[a1,a2,a3],
                          Tuple_v[b1,b2,b3]]) =>
                 let val (a1,a2,a3) = (toReal s a1,toReal s a2,toReal s a3)
                     val (b1,b2,b3) = (toReal s b1,toReal s b2,toReal s b3)
                     val (r1,r2,r3) = opr ((a1,a2,a3),(b1,b2,b3))
                 in Tuple_v[Real_v r1,Real_v r2,Real_v r3]
                 end
               | _ => raise Fail ("eval: " ^ s ^ " expects a pair of two triples of reals")))

fun lift_r3xr3_r s (opr : (real*real*real) * (real*real*real) -> real) : string * v =
    (s, Fun_v(fn (Tuple_v[Tuple_v[a1,a2,a3],
                          Tuple_v[b1,b2,b3]]) =>
                 let val (a1,a2,a3) = (toReal s a1,toReal s a2,toReal s a3)
                     val (b1,b2,b3) = (toReal s b1,toReal s b2,toReal s b3)
                     val r' = opr ((a1,a2,a3),(b1,b2,b3))
                 in Real_v r'
                 end
               | Zero_v => Zero_v
               | _ => raise Fail ("eval: " ^ s ^ " expects a pair of two triples of reals")))

fun lift_rNxrN_rN s (opr : real list * real list -> real list) : string * v =
    (s, Fun_v(fn (Tuple_v[Array_v vs1,
                          Array_v vs2]) =>
                 let val rs1 = map (toReal s) vs1
                     val rs2 = map (toReal s) vs2
                     val rs = opr (rs1,rs2)
                 in Array_v (map Real_v rs)
                 end
               | _ => raise Fail ("eval: " ^ s ^ " expects a pair of two real arrays")))

val VEinit : v env =
    [lift1r "abs" (fn r => if r < 0.0 then ~r else r),
     lift1r "sin" Math.sin,
     lift1r "cos" Math.cos,
     lift1r "tan" Math.tan,
     lift1r "exp" Math.exp,
     lift1r "ln" Math.ln,
     lift_rNxrN_r "dprod" (ListPair.foldlEq(fn (r1,r2,a) => a + (r1*r2)) 0.0),
     lift_rxrN_rN "sprod" (fn (r,rs) => List.map (fn q => q*r) rs),
     lift_r3xr3_r3 "cprod3" (fn ((a1,a2,a3),(b1,b2,b3)) =>
                                (a2*b3-a3*b2, a3*b1-a1*b3, a1*b2-a2*b1)),
     lift_r3xr3_r "dprod3" (fn ((a1,a2,a3),(b1,b2,b3)) => (a1*b1+a2*b2+a3*b3)),
     lift_rNxrN_rN "cross" (fn ([a1,a2,a3],[b1,b2,b3]) =>
                               [a2*b3-a3*b2, a3*b1-a1*b3, a1*b2-a2*b1]
                           | _ => raise Fail ("eval: cross is defined only in the three dimensional space")),
     lift_rxr_r "norm2sq" (fn (r1,r2) => Math.sqrt(r1*r1+r2*r2)),
     ("pi", Real_v (Math.pi))]

val VEempty : v env = nil

fun look nil x = NONE
  | look ((k,v)::E) x = if k = x then SOME v else look E x

fun insert (E: 'a env) (k:string,v:'a) : 'a env = (k,v)::E

fun plus (E1, E2) = E2 @ E1

fun liftNeg i v : v =
    case v of
        Real_v r => Real_v(~r)
      | Tuple_v vs => Tuple_v (List.map (liftNeg i) vs)
      | Array_v vs => Array_v (List.map (liftNeg i) vs)
      | Zero_v => Zero_v
      | _ => dieReg i "liftNeg: expecting structured real value"

fun liftSub i (v1,v2) : v =
    case (v1,v2) of
        (Real_v r1, Real_v r2) => Real_v(r1-r2)
      | (Tuple_v vs1, Tuple_v vs2) =>
        (Tuple_v (ListPair.mapEq (liftSub i) (vs1,vs2))
         handle ListPair.UnequalLengths =>
                dieReg i "liftSub: expecting tuples of equal lengths")
      | (Array_v vs1, Array_v vs2) =>
        (Array_v (ListPair.mapEq (liftSub i) (vs1,vs2))
         handle ListPair.UnequalLengths =>
                dieReg i "liftSub: expecting arrays of equal lengths")
      | (v1,Zero_v) => v1
      | (Zero_v,v2) => liftNeg i v2
      | _ => dieReg i "liftSub: expecting matching structured values"

fun liftAdd i (v1,v2) : v =
    case (v1,v2) of
        (Real_v r1, Real_v r2) => Real_v(r1+r2)
      | (Tuple_v vs1, Tuple_v vs2) =>
        (Tuple_v (ListPair.mapEq (liftAdd i) (vs1,vs2))
         handle ListPair.UnequalLengths =>
                dieReg i "liftAdd: expecting tuples of equal lengths")
      | (Array_v vs1, Array_v vs2) =>
        (Array_v (ListPair.mapEq (liftAdd i) (vs1,vs2))
         handle ListPair.UnequalLengths =>
                dieReg i "liftAdd: expecting arrays of equal lengths")
      | (Zero_v,v2) => v2
      | (v1,Zero_v) => v1
      | _ => dieReg i "liftAdd: expecting matching structured values"

fun liftMulPow i opr v : v =
    case v of
        Real_v r => Real_v (opr r)
      | Tuple_v vs => Tuple_v (map (liftMulPow i opr) vs)
      | Array_v vs => Array_v (map (liftMulPow i opr) vs)
      | Zero_v => Zero_v (* ok for mul and pow *)
      | _ => dieReg i "liftMulPow: expecting structured value of reals"

fun eval (regof:'i -> Region.reg) (E:v env) (e:'i exp) : v =
    let fun ev E e =
            case e of
                Real (r,_) => Real_v r
              | Zero r => Zero_v
              | Let (x,e1,e2,_) => ev ((x,ev E e1)::E) e2
              | Var (x,i) =>
                (case look E x of
                     SOME v => v
                   | NONE => dieReg (regof i) ("unknown variable: " ^ x))
              | Add (e1,e2,i) => liftAdd (regof i) (ev E e1, ev E e2)
              | Sub (e1,e2,i) => liftSub (regof i) (ev E e1, ev E e2)
              | Mul (e1,e2,i) =>
                (case ev E e1 of
                     Real_v r => liftMulPow (regof i) (fn r' => r * r') (ev E e2)
                   | _ => dieReg (regof i) ("expecting real as left argument to mul"))
              | App (f,e,i) => (case look E f of
                                    SOME(Fun_v f) => f (ev E e)
                                  | SOME _ => dieReg (regof i) ("expecting function but found " ^ f)
                                  | NONE => dieReg (regof i) ("unknown function: " ^ f))
              | Tuple (es,_) => Tuple_v (map (ev E) es)
              | Prj (i,e,info) => (case ev E e of
                                       Tuple_v vs => (List.nth (vs,i-1)
                                                      handle _ =>
                                                             dieReg (regof info) ("index (1-based) out of bound"))
                                     | Zero_v => Zero_v
                                     | _ => dieReg (regof info) "expecting tuple")
	      | Map (x,f,es,info) =>
                (case ev E es of
                     Array_v vs => Array_v (List.map (fn v => ev (insert E (x, v)) f) vs)
                   | Zero_v => Zero_v
                   | _  => dieReg (regof info) "expecting array"
                )
	      | Iota (n,_) => Array_v (List.tabulate (n, real_v o Real.fromInt))
              | Pow (r,e,i) => liftMulPow (regof i)
                                          (fn r' => Math.pow(r',r))
                                          (ev E e)
    in ev E e
    end

fun locOfTs nil = Region.botloc
  | locOfTs ((_,(l,_))::_) = l

val kws = ["let", "in", "end", "fun", "map", "iota", "fn", "pow"]

val p_zero : unit p =
 fn ts =>
    case ts of
        (T.Num "0",r)::ts' => OK ((),r,ts')
      | _ => NO(locOfTs ts, fn () => "zero")

val p_int : int p =
 fn ts =>
    case ts of
        (T.Num n,r)::ts' =>
        (case Int.fromString n of
             SOME n => OK (n,r,ts')
           | NONE => NO(locOfTs ts, fn () => "int"))
      | _ => NO(locOfTs ts, fn () => "int")

val p_real : real p =
 fn ts =>
    case ts of
        (T.Num n,r)::ts' =>
        (case Real.fromString n of
             SOME n => OK (n,r,ts')
           | NONE => NO(locOfTs ts, fn () => "real"))
      | _ => NO(locOfTs ts, fn () => "real")

val p_kw : string -> unit p =
 fn s => fn ts =>
    case ts of
        (T.Id k,r)::ts' =>
        if k = s then OK ((),r,ts')
        else NO(locOfTs ts, fn () => "expecting keyword '" ^ s ^ "', but found identifier '" ^ k ^ "'")
      | _ => NO(locOfTs ts, fn () => "expecting keyword '" ^ s ^ "', but found number or symbol")

val p_var : string p =
 fn ts =>
    case ts of
        (T.Id k,r)::ts' =>
        if not (List.exists (fn s => s = k) kws) then OK (k,r,ts')
        else NO(locOfTs ts, fn () => "expecting identifier, but found keyword '" ^ k ^ "'")
      | _ => NO(locOfTs ts, fn () => "expecting identifier, but found number or symbol")

val p_symb : string -> unit p =
 fn s => fn ts =>
    case ts of
        (T.Symb k,r)::ts' =>
        if k = s then OK ((),r,ts')
        else NO(locOfTs ts, fn () => "symb1")
      | (T.Id k,r)::_ => NO(locOfTs ts, fn () => ("symb: found id " ^ k))
      | _ => NO(locOfTs ts, fn () => "symb2")

infix >>> ->> >>- oo oor || ?? ??*

fun p_seq start finish (p: 'a p) : 'a list p =
    fn ts =>
       ((((((p_symb start ->> p) oo (fn x => [x])) ??* (p_symb "," ->> p)) (fn (xs,x) => x::xs)) >>- p_symb finish) oo List.rev)
           ts

type rexp = Region.reg exp

val rec p_e : rexp p =
    fn ts =>
       ( (p_e0 ??* ((p_bin "+" Add p_e0) || (p_bin "-" Sub p_e0))) (fn (e,f) => f e)
       ) ts

and p_e0 : rexp p =
    fn ts =>
       ( (p_ae ??* p_bin "*" Mul p_ae) (fn (e,f) => f e)
       ) ts

and p_ae : rexp p =
    fn ts =>
       (    ((p_var >>> p_ae) oor (fn ((v,e),r) => App(v,e,r)))
         || (((p_kw "pow" ->> p_real) >>> p_ae) oor (fn ((f,e),r) => Pow(f,e,r)))
         || (p_var oor Var)
         || (p_zero oor (fn ((),i) => Zero i))
         || (p_real oor Real)
         || (((p_symb "#" ->> p_int) >>> p_ae) oor (fn ((i,e),r) => Prj(i,e,r)))
         || ((p_seq "(" ")" p_e) oor (fn ([e],_) => e | (es,r) => Tuple (es,r)))
         || (((p_kw "let" ->> p_var) >>> ((p_symb "=" ->> p_e) >>> (p_kw "in" ->> p_e)) >>- p_kw "end") oor (fn ((v,(e1,e2)),r) => Let(v,e1,e2,r)))
         || (((p_kw "map" ->> ((p_symb "("
                              ->> (((p_kw "fn" ->> p_var) >>- p_symb "=>") >>> p_e))
                              >>- p_symb ")")) >>> p_ae)
                              oor (fn (((x, f), e), r) => Map (x, f, e, r)))
         || ((p_kw "iota" ->> p_int) oor (fn (n, r) => Iota (n, r)))
      ) ts

and p_bin : string -> (rexp*rexp*Region.reg->rexp) -> rexp p -> (rexp -> rexp) p =
 fn opr => fn f => fn p =>
 fn ts =>
    ( (p_symb opr ->> p) oor (fn (e2,r) => fn e1 => f(e1,e2,r))
    ) ts

fun parse0 (p: 'a p) {srcname,input} : 'a =
    let val ts = lexing {srcname=srcname,input=input}
    in case p ts of
           NO(l,f) => dieLoc l (f())
         | OK(e,r,ts') =>
           case ts' of
               nil => e
             | _ => ( prTokens ts
                    ; dieLoc (#2 r) "syntax error"
                    )
    end

fun parse arg = parse0 p_e arg

(* ------------- *)
(* Programs      *)
(* ------------- *)

type 'i prg = (string * string * 'i exp * 'i) list

type rprg = Region.reg prg

val rec p_prg : rprg p =
    fn ts =>
       (  ((((((p_kw "fun" ->> p_var) >>> p_var) >>- p_symb "=") >>> p_e) oor (fn (((f,x),e),r) => [(f,x,e,r)])) ??* p_prg) (op @)
       ) ts

fun pr_prg (p: 'i prg) : string =
  case p of
     nil => ""
   | ((f,x,e,_)::ps) => "fun " ^ f ^ " " ^ x ^ " = " ^ pr_exp e  ^ "\n" ^ pr_prg ps

val parse_prg = parse0 p_prg

fun eval_prg (regof:'i->Region.reg) (prg: 'i prg) (f:string) (v:v) : v =
    let fun addFun ((f,x,e,_),VE:v env) : v env =
            insert VE (f,Fun_v(fn v => eval regof (insert VE (x,v)) e))
        val E = List.foldl addFun VEinit prg
    in case look E f of
           SOME (Fun_v f) => f v
         | SOME _ => raise Fail ("eval_prg: expecting function " ^ f)
         | NONE => raise Fail ("eval_prg: unknown function " ^ f)
    end

fun eval_exp (regof:'i->Region.reg) (prg: 'i prg) (e: 'i exp) : v =
    let fun addFun ((f,x,e,_),VE:v env) : v env =
            insert VE (f,Fun_v(fn v => eval regof (insert VE (x,v)) e))
        val E = List.foldl addFun VEinit prg
    in eval regof E e
    end

(* -------------- *)
(* Type inference *)
(* -------------- *)

datatype tinfo = Real_ti
               | Tuple_ti of ty list
               | Fun_ti of ty * ty
               | Tvar_ti of int * constraint list
               | Array_ti of ty
     and constraint =
         NonFun
       | ElemTy of int * ty
withtype ty = tinfo URef.uref

val fresh_ty : unit -> ty =
 let val c = ref 0
 in fn () =>
       ( c := !c + 1
       ; URef.uref(Tvar_ti (!c,nil))
       )
 end

val real_ty : ty = URef.uref Real_ti

fun tuple_ty (ts : ty list) : ty =
    URef.uref (Tuple_ti ts)

fun fun_ty (t1:ty, t2:ty) : ty =
    URef.uref (Fun_ti (t1,t2))

fun array_ty (ty:ty) : ty =
    URef.uref (Array_ti ty)

fun un_tuple (ty:ty) : ty list option =
    case URef.!! ty of
        Tuple_ti tys => SOME tys
      | _ => NONE

fun un_array (ty:ty) : ty option =
    case URef.!! ty of
        Array_ti ty => SOME ty
      | _ => NONE

fun un_fun (ty:ty) : (ty*ty) option =
    case URef.!! ty of
        Fun_ti tys => SOME tys
      | _ => NONE

fun is_real (ty:ty) : bool =
    case URef.!! ty of
        Real_ti => true
      | _ => false

fun pair_ty(t1,t2) = tuple_ty[t1,t2]
val real3_ty = tuple_ty[real_ty,real_ty,real_ty]

val real_arr_ty = array_ty real_ty

val TEinit : ty env =
    [("abs", fun_ty(real_ty,real_ty)),
     ("sin", fun_ty(real_ty,real_ty)),
     ("cos", fun_ty(real_ty,real_ty)),
     ("tan", fun_ty(real_ty,real_ty)),
     ("exp", fun_ty(real_ty,real_ty)),
     ("ln", fun_ty(real_ty,real_ty)),
     ("cprod3", fun_ty(pair_ty(real3_ty,real3_ty),real3_ty)),
     ("cross", fun_ty(pair_ty(real_arr_ty,real_arr_ty),real_arr_ty)),  (* cprod3 on arrays *)
     ("dprod3", fun_ty(pair_ty(real3_ty,real3_ty),real_ty)),
     ("dprod", fun_ty(pair_ty(real_arr_ty,real_arr_ty),real_ty)),
     ("sprod", fun_ty(pair_ty(real_ty,real_arr_ty),real_arr_ty)),
     ("norm2sq", fun_ty(pair_ty(real_ty,real_ty),real_ty)),
     ("pi", real_ty)]

val TEempty : ty env = nil

fun eq_ty (t1,t2) : bool =
    URef.eq (t1,t2) orelse
    case (URef.!! t1, URef.!! t2) of
        (Real_ti, Real_ti) => true
      | (Tuple_ti ts1, Tuple_ti ts2) => eq_tys (ts1,ts2)
      | (Fun_ti (t1,t2),Fun_ti(t1',t2')) =>
        eq_ty(t1,t1') andalso eq_ty(t2,t2')
      | (Array_ti t1, Array_ti t2) => eq_ty (t1, t2)
      | _ => false
and eq_tys (nil,nil) = true
  | eq_tys (t1::ts1,t2::ts2) = eq_ty(t1,t2) andalso eq_tys(ts1,ts2)
  | eq_tys _ = false

fun pr_ty ty = pr_ti(URef.!! ty)
and pr_ti ti =
    case ti of
        Real_ti => "real"
      | Tuple_ti ts => "(" ^ String.concatWith " * " (map pr_ty ts) ^ ")"
      | Fun_ti(t1,t2) =>  "(" ^ pr_ty t1 ^ " -> " ^ pr_ty t2 ^ ")"
      | Tvar_ti (i,_) =>  "'a" ^ Int.toString i
      | Array_ti t => "[]" ^ pr_ty t

fun unify_ty (r:Region.reg) (t1,t2) : unit =
    URef.unify (fn (Real_ti,Real_ti) => Real_ti
                 | (ti as Tuple_ti ts1, Tuple_ti ts2) =>
                   ( unify_tys r (ts1,ts2) ; ti )
                 | (ti as Fun_ti(t1,t2), Fun_ti(t1',t2')) =>
                   ( unify_ty r (t1,t1') ; unify_ty r (t2,t2') ; ti )
		 | (ti as Array_ti t1, Array_ti t2) => (unify_ty r (t1, t2); ti)
                 | (Tvar_ti (i1,cs1), Tvar_ti (i2,cs2)) => Tvar_ti (Int.min(i1,i2), cs1 @ cs2)
                 | (Tvar_ti (_,cs), ti) => ( List.app (chk_constraint r ti) cs ; ti )
                 | (ti, Tvar_ti (_,cs)) => ( List.app (chk_constraint r ti) cs ; ti )
                 | _ => dieReg r ("failed to unify " ^ pr_ty t1 ^ " with " ^ pr_ty t2)
               ) (t1,t2)
and unify_tys r (ts1,ts2) =
    let fun f (nil,nil) = ()
          | f (t1::ts1,t2::ts2) = (unify_ty r (t1,t2) ; f (ts1,ts2) )
          | f _ = dieReg r ("failed to unify tuple type " ^ pr_ti (Tuple_ti ts1) ^
                            " with tuple type " ^ pr_ti (Tuple_ti ts2) ^
                            " of a different length")
    in f (ts1,ts2)
    end
and chk_constraint (r:Region.reg) ti c =
    case (c,ti) of
        (NonFun, Fun_ti _) => dieReg r "expecting non-function"
      | (NonFun, _) => () (* maybe check recursively and add new constraints to type variables *)
      | (ElemTy(i,ty), Tuple_ti tys) =>
        let val ty' = List.nth(tys,i-1)
                      handle _ =>
                             dieReg r ("tuple projection " ^ Int.toString i ^
                                       " out of bound: tuple contains only " ^
                                       Int.toString (length tys) ^ " elements")
        in unify_ty r (ty,ty')
        end
      | (ElemTy(i,ty), _) => dieReg r ("expecting tuple type but found " ^ pr_ti ti)

fun unify_prj_ty (r:Region.reg) (i,ty,tuplety) =
    case URef.!! tuplety of
        Tuple_ti tys =>
        let val ty' = List.nth(tys,i-1)
                      handle _ =>
                             dieReg r ("tuple projection " ^ Int.toString i ^
                                       " out of bound: tuple contains only " ^
                                       Int.toString (length tys) ^ " elements")
        in unify_ty r (ty,ty')
        end
      | Tvar_ti(tv,cs) =>
        let val c = ElemTy(i,ty)
        in URef.::= (tuplety, Tvar_ti(tv,c::cs))
        end
      | _ => dieReg r ("failed to project from non-tuple type " ^ pr_ty tuplety)

fun info_of_exp (e: 'i exp) : 'i =
    case e of
        Real(_,i) => i
      | Zero i => i
      | Let(_,_,_,i) => i
      | Add(_,_,i) => i
      | Sub(_,_,i) => i
      | Mul(_,_,i) => i
      | Var (_,i) => i
      | App(_,_,i) => i
      | Tuple (_,i) => i
      | Prj(_,_,i) => i
      | Map(_,_,_,i) => i
      | Iota(_,i)  => i
      | Pow(_,_,i) => i

fun tyinf_exp (TE: ty env) (e:Region.reg exp) : (Region.reg*ty) exp * ty =
    let fun tyinf_svbin opr (e1,e2,r) =
            let val (e1',ty1) = tyinf_exp TE e1
                val (e2',ty2) = tyinf_exp TE e2
            in unify_ty (info_of_exp e1) (ty1,real_ty)
             ; (opr (e1',e2',(r,ty2)), ty2)
            end
        fun tyinf_vbin opr (e1,e2,r) =
            let val (e1',ty1) = tyinf_exp TE e1
                val (e2',ty2) = tyinf_exp TE e2
            in unify_ty (info_of_exp e2) (ty1,ty2)
             ; (opr (e1',e2',(r,ty1)), ty1)
            end
    (* Several operators (and values) are generic:
        - Add : 'a * 'a -> 'a
        - Sub : 'a * 'a -> 'a
        - 0 : 'a
        - Mul : real * 'a -> 'a
     *)
    in case e of
           Real (f,r) => (Real (f,(r,real_ty)), real_ty)
         | Zero r =>
           let val t = fresh_ty()
           in (Zero (r,t), t)
           end
         | Let (x,e1,e2,r) =>
           let val (e1',ty1) = tyinf_exp TE e1
               val (e2',ty2) = tyinf_exp (insert TE (x,ty1)) e2
           in (Let (x,e1',e2',(r,ty2)), ty2)
           end
         | Add (e1,e2,r) => tyinf_vbin Add (e1,e2,r)
         | Sub (e1,e2,r) => tyinf_vbin Sub (e1,e2,r)
         | Mul (e1,e2,r) => tyinf_svbin Mul (e1,e2,r)
         | Var (x,r) => (case look TE x of
                             SOME ty => (Var(x,(r,ty)),ty)
                           | NONE => dieReg r ("unknown variable: " ^ x))
         | App (f,e1,r) =>
           let val (e1',ty1) = tyinf_exp TE e1
           in case look TE f of
                  SOME tf =>
                  let val ty2 = fresh_ty()
                  in unify_ty r (tf,fun_ty(ty1,ty2))
                   ; (App(f,e1',(r,ty2)), ty2)
                  end
                | NONE => dieReg r ("unknown function: " ^ f)
           end
         | Tuple (es,r) =>
           let val ets = List.map (tyinf_exp TE) es
               val t = tuple_ty (map #2 ets)
           in (Tuple (map #1 ets,(r,t)), t)
           end
         | Prj (i,e1,r) =>
           let val (e1',ty1) = tyinf_exp TE e1
               val t = fresh_ty()
           in unify_prj_ty r (i,t,ty1)
            ; (Prj(i,e1',(r,t)),t)
           end
         | Iota (n,r) =>
               (Iota(n, (r, array_ty real_ty)), array_ty real_ty)
         | Map (x,f,es,r) =>
           let val ty_x = fresh_ty()
               val (f', ty_f) = tyinf_exp (insert TEinit (x, ty_x)) f
               val (es', ty_es) = tyinf_exp TE es
           in unify_ty r (ty_es, array_ty ty_x)
            ; (Map (x, f', es', (r, array_ty ty_f)), array_ty ty_f)
           end
         | Pow (f,e1,r) =>
           let val (e1',ty1) = tyinf_exp TE e1
           in unify_ty r (ty1,real_ty)
            ; (Pow (f,e1',(r,real_ty)), real_ty)
           end
    end

val fresh_ty_nonfun = fresh_ty (* MEMO: add constraint *)

val reg0 = (Region.botloc,Region.botloc)

(* Resolve non-instantiated type variables by analysing the
 * type constraints; non-constrained type variables are instantiated
 * to type real. Projection constraints guide the number of elements
 * and the element types in each tuple type. Notice: Projections
 * project from tuples, not from arrays. *)

fun resolve_t t =
    case URef.!! t of
        Tvar_ti (_, cs) =>
        let val m = List.foldl (fn (c,m) =>
                                   case c of
                                       NonFun => m
                                     | ElemTy(i,_) => Int.max(i,m)) 0 cs
            fun look j cs =
                case cs of
                    nil => NONE
                  | NonFun :: cs => look j cs
                  | ElemTy(i,t) :: cs => if j = i then SOME t
                                         else look j cs
        in if m = 0 then URef.::=(t, Real_ti)
           else
             let val m = Int.max(2,m) (* at least two elements *)
                 val ts = List.tabulate(m, fn i => case look (i+1) cs of
                                                       SOME t => t
                                                     | NONE => real_ty)
             in unify_ty reg0 (tuple_ty ts, t)
              ; app resolve_t ts
             end
        end
      | Real_ti => ()
      | Tuple_ti ts => List.app resolve_t ts
      | Fun_ti(t1,t2) => (resolve_t t1 ; resolve_t t2)
      | Array_ti t => resolve_t t

fun resolve_e (e : (Region.reg*ty) exp) : unit =
    let val (_,t) = info_of_exp e
    in resolve_t t
    end

(* General type inference function *)
fun tyinf_prg (prg: Region.reg prg) : (Region.reg*ty) prg * ty env =
    let fun tyinf TE ((f,x,e,r)::rest) (prg_acc,TEacc) =
            let val ty = fresh_ty_nonfun()
                val (e',ty') = tyinf_exp (insert TE (x,ty)) e
                val fty = fun_ty(ty,ty')
                val TE' = insert TE (f, fty)
                val TEacc' = insert TEacc (f, fty)
                val prg_acc' = (f,x,e',(r,fty)) :: prg_acc
            in tyinf TE' rest (prg_acc',TEacc')
            end
          | tyinf _ nil (prg_acc,TEacc) = (rev prg_acc,TEacc)
        val (prg',TE) = tyinf TEinit prg (nil,TEempty)
        val () = List.app (fn (_,_,e',(_,fty)) =>
                              ( resolve_e e'
                              ; resolve_t fty )
                          ) prg'
    in (prg',TE)
    end

end
