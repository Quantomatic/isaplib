(* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- *)
signature BNF_Morphisms
= sig

exception bad_dcx_exp of string * Data.dname * Data.dcontext;

(* transform a bnf to remove epsilons *)
val elim_epsilon : Data.dcontext -> Data.dcontext

(* epsilon is called "unit" *)
val unit_id : string
val unit_dname : Data.dname

(* Compressor/Make Efficient *)
(* IDEA: add grammar compression: move non-deturminism to leaves,
e.g. consider case insensitive morphism, make sure non-deturminism is
at letter-level, not every case-combo for whole string. *)

(* Add whitespace *)
(* IDEA: transforms a grammar to allow white space between all token
types - checks that white space is not "needed" in some places. Maybe
need to say which tokens you can separate with whitespace. *)

(* internal *)
val remove_all_etab_dnames : Data.dname -> Data.dname EnTab.T -> Data.dname EnTab.T 
val remove_all_ctab_dnames : Data.dname -> Data.dname CnTab.T -> Data.dname CnTab.T 

end;


(* -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- *)
structure DB_BNFMorphisms
= struct

exception bad_dcx_exp of string * Data.dname * Data.dcontext;

val unit_id = Data.unit_id;
val unit_dname = Data.unit_dname;

(* remove every drop_dn from elem table *)
fun remove_all_etab_dnames drop_dn etab = 
    EnTab.fold 
      (fn (en,dn) => fn etab2 =>
          if Dn.name_eq (dn, drop_dn) then 
            EnTab.delete en etab2
          else etab2)
      etab
      etab;

(* remove every drop_dn from constructor table *)
fun remove_all_ctab_dnames drop_dn ctab = 
    CnTab.fold 
      (fn (cn,dn) => fn ctab2 =>
          if Dn.name_eq (dn, drop_dn) then 
            CnTab.delete cn ctab2
          else ctab2)
      ctab
      ctab;

(* make optdn an optional name in etab; returns a list containing an
   etab for every subset of deletions of optdn *)
fun mk_optional_in_etab optdn etab = 
    let 
      val positions_of_dn = 
          EnTab.fold 
            (fn (en,dn) => if Dn.name_eq (dn,optdn) then
                             En.NSet.add en else I)
            etab
            En.NSet.empty
      fun drop_poses etab drop_poses = 
          En.NSet.fold EnTab.delete drop_poses etab;
    in
      map (drop_poses etab) (En.NSet.powerset positions_of_dn)
    end;

(* make optdn optional in dn; if dn is and-type this explodes into all
   possibilities where optdn is dropped; is dn is or-type then we just
   give it back in more_opts as another thing that might be empty *)
fun mk_optional_in_dn optdn dn (more_opts, dcx : Data.dcontext) = 
    case Data.get_datatyp dcx dn of 
      Data.BType _ => raise bad_dcx_exp ("elim_1epsilon", dn, dcx)
    | Data.Ors _ => 
      (dn::more_opts, dcx)
    | Data.Ands etab => 
      let val etabl = mk_optional_in_etab optdn etab
          val (or_dns, dcx2) =
              fold 
                (fn etab => fn (or_dns,dcx2) => 
                    let val (newdn, dcx3) = 
                            Data.addfresh_datatyp 
                              (Dn.mk ((Dn.dest dn) ^ ".a"), 
                               Data.Ands etab) dcx2
                    in (Dn.NSet.add newdn or_dns, dcx3) end)
                etabl
                (Dn.NSet.empty, dcx)

          val ctab = 
              Dn.NSet.fold
                (fn newdn => fn ctab => CnTab.doadd (Cn.mk "1",newdn) ctab)
                or_dns
                CnTab.empty
      in 
        (more_opts, 
         dcx2 |> Data.del_data dn
              |> Data.add_datatyp (dn, Data.Ors ctab))
      end;

(* for the identity group of or-choices; make the optdn an optional
type everywhere it is used.

(an identiy or-choice group has the form
   {A ::= B | ... ; B ::= A | ... })
*)
fun mk_optional_everywhere optdn (done_dns,dcx) = 
    if Dn.NSet.contains done_dns optdn 
    then (done_dns, dcx) else 
    let 
      val parents = Data.parents_of_data (Data.get dcx optdn)
      val done_dns2 = Dn.NSet.add optdn done_dns
      val (more_otps, dcx2) = 
          Dn.NSet.fold 
            (mk_optional_in_dn optdn)
            parents
            ([], dcx)
    in
      fold mk_optional_everywhere more_otps (done_dns2, dcx2)
    end;

(* eliminate or-unit (empty string/epsilon) from n; *)
fun elim_1epsilon n dcx = 
    let val d = Data.get dcx n
        val dtyp = Data.datatyp_of_data d;
    in
      case dtyp of
        Data.BType _ => raise bad_dcx_exp ("elim_1epsilon", n, dcx)
      | Data.Ors ctab => 
        let val ctab2 = remove_all_ctab_dnames unit_dname ctab
            val (donedns, dcx2) = mk_optional_everywhere n (Dn.NSet.empty, dcx)
        in dcx2 |> Data.del_data n
                |> Data.add_datatyp (n,Data.Ors ctab2)
        end
      | Data.Ands etab => 
        let val etab2 = remove_all_etab_dnames unit_dname etab
        in dcx |> Data.del_data n
               |> Data.add_datatyp (n,Data.Ands etab2)
        end
    end;

(* eliminate/expand-out all unit/epsilon references *)
fun elim_epsilon dcx = 
    Dn.NSet.fold 
      elim_1epsilon
      (Data.parents_of_data (Data.get dcx unit_dname))
      dcx;

end;


structure BNFMorphisms : BNF_Morphisms = DB_BNFMorphisms;
