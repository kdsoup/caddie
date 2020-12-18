signature LIN = sig
  type v
  type lin
  type 'a M

  (* Constructors *)
  val lin   : string * (v -> v) -> lin
  val prj   : int -> int -> lin   (* prj dim idx *)
  val zero  : lin
  val id    : lin
  val oplus : lin * lin -> lin
  val comp  : lin * lin -> lin
  val curL  : Prim.bilin * v -> lin   (* ( v * ) *)
  val curR  : Prim.bilin * v -> lin   (* ( * v ) *)

  (* some linear primitives *)
  val add   : lin
  val dup   : lin
  val neg   : lin

  val iff   : v * lin M * lin M -> lin

  val pp    : lin -> string
  val eval  : lin -> v -> v M

  val transp : lin -> lin
end
