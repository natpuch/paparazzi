(*
 * Copyright (C) 2003-2009 Pascal Brisset, Antoine Drouin, ENAC
 * Copyright (C) 2017 Gautier Hattenberger <gautier.hattenberger@enac.fr>
 *                    Cyril Allignol <cyril.allignol@enac.fr>
 *
 * This file is part of paparazzi.
 *
 * paparazzi is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 *
 * paparazzi is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with paparazzi; see the file COPYING.  If not, see
 * <http://www.gnu.org/licenses/>.
 *)

(**
 * Main generator tool
 *)


open Printf
module U = Unix

open Gen_common

let (//) = Filename.concat

let paparazzi_conf = Env.paparazzi_home // "conf"
let default_conf_xml = paparazzi_conf // "conf.xml"

let airframe_h = "airframe.h"
let radio_h = "radio.h"
let periodic_h = "periodic_telemetry.h"
let default_periodic_freq = 60

let get_string_opt = fun x -> match x with Some s -> s | None -> ""

type t = {
  airframe: Airframe.t option;
  flight_plan: Flight_plan.t option;
  settings: Settings.t list;
  radio: Radio.t option;
  telemetry: Telemetry.t option;
}

let mkdir = fun d ->
  assert (Sys.command (sprintf "mkdir -p %s" d) = 0)

(** Raises a Failure if an ID or a NAME appears twice in the conf *)
let check_unique_id_and_name = fun conf conf_xml ->
  let ids = Hashtbl.create 5 and names = Hashtbl.create 5 in
  ExtXml.iter_tag "aircraft"
    (fun x ->
      let id = ExtXml.attrib x "ac_id"
      and name = ExtXml.attrib x "name" in
      if Hashtbl.mem ids id then begin
        let other_name = Hashtbl.find ids id in
        failwith (sprintf "Error: A/C Id '%s' duplicated in %s (%s and %s)" id conf_xml name other_name)
      end;
      if Hashtbl.mem names name then begin
        let other_id = Hashtbl.find names name in
        failwith (sprintf "Error: A/C name '%s' duplicated in %s (ids %s and %s)" name conf_xml id other_id)
      end;
      Hashtbl.add ids id name;
      Hashtbl.add names name id
    ) conf


let is_older = fun target_file dep_files ->
  not (Sys.file_exists target_file) ||
    let target_file_time = (U.stat target_file).U.st_mtime in
    let rec loop = function
      | [] -> false
      | f :: fs -> target_file_time < (U.stat f).U.st_mtime || loop fs in
    loop dep_files

let make_element = fun t a c -> Xml.Element (t,a,c)

(** Extract a configuration element from aircraft config,
 *  returns a tuple with absolute file path and element object
 * 
 * [bool -> Xml.xml -> string -> (Xml.xml -> a') -> (string * a' option)]
 *)
let get_config_element = fun flag ac_xml elt f ->
  if flag then
    ("", None) (* generation is not requested *)
  else
    try
      let file = Xml.attrib ac_xml elt in
      let abs_file = paparazzi_conf // file in
      let xml = ExtXml.parse_file abs_file in
      (abs_file, Some (f xml))
    with Xml.No_attribute _ -> ("", None) (* no attribute elt in conf file *)

(** Generate a configuration element
 *  Also check dependencies
 *
 * [a' option -> (a' -> unit) -> (string * string list) list -> unit]
 *)
let generate_config_element = fun elt f dep_list ->
  match elt with
  | None -> ()
  | Some e ->
      if List.exists (fun (file, dep) -> is_older file dep) dep_list then f e
      else ()

(******************************* MAIN ****************************************)
let () =
  let ac_name = ref None
  and conf_xml = ref default_conf_xml
  and target = ref ""
  and gen_af = ref false
  and gen_fp = ref false
  and gen_set = ref false
  and gen_rc = ref false
  and gen_tl = ref false
  and tl_freq = ref default_periodic_freq in

  let options =
    [ "-name", Arg.String (fun x -> ac_name := Some x), "Aircraft name (mandatory)";
      "-conf", Arg.String (fun x -> conf_xml := x), (sprintf "Configuration file (default '%s')" default_conf_xml);
      "-target", Arg.String (fun x -> target := x), "Target to build";
      "-airframe", Arg.Set gen_af, "Generate airframe file";
      "-flight_plan", Arg.Set gen_fp, "Generate flight plan file";
      "-settings", Arg.Set gen_set, "Generate settings file";
      "-radio", Arg.Set gen_set, "Generate radio file";
      "-telemetry", Arg.Set gen_tl, "Generate telemetry file";
      "-periodic_freq", Arg.Int (fun x -> tl_freq := x), (sprintf "Periodic telemetry frequency (default %d)" default_periodic_freq)
      ] in

  Arg.parse
    options
    (fun x -> Printf.fprintf stderr "%s: Warning: Don't do anything with '%s' argument\n" Sys.argv.(0) x)
    "Usage: ";

  let aircraft =
    match !ac_name with
    | None -> failwith "An aircraft name is mandatory"
    | Some ac -> ac
  in
  try
    let conf = ExtXml.parse_file !conf_xml in
    check_unique_id_and_name conf !conf_xml;
    let aircraft_xml =
      try
        ExtXml.child conf ~select:(fun x -> Xml.attrib x "name" = aircraft) "aircraft"
      with
        Not_found -> failwith (sprintf "Aircraft '%s' not found in '%s'" aircraft !conf_xml)
    in

    let value = fun attrib -> ExtXml.attrib aircraft_xml attrib in

    (* Prepare building folders *)
    let aircraft_dir = Env.paparazzi_home // "var" // "aircrafts" // aircraft in
    let aircraft_conf_dir = aircraft_dir // "conf" in
    let aircraft_gen_dir = aircraft_dir // !target // "generated" in
    mkdir (Env.paparazzi_home // "var");
    mkdir (Env.paparazzi_home // "var" // "aircrafts");
    mkdir aircraft_dir;
    mkdir (aircraft_dir // !target);
    mkdir aircraft_conf_dir;
    mkdir (aircraft_conf_dir // "airframes");
    mkdir (aircraft_conf_dir // "flight_plans");
    mkdir (aircraft_conf_dir // "radios");
    mkdir (aircraft_conf_dir // "settings");
    mkdir (aircraft_conf_dir // "telemetry");

    (* Parse file if needed *)
    let abs_airframe_file, airframe = get_config_element !gen_af aircraft_xml "airframe" Airframe.from_xml in
    let abs_fp_file, flight_plan = get_config_element !gen_fp aircraft_xml "flight_plan" Flight_plan.from_xml in
    let abs_radio_file, radio = get_config_element !gen_rc aircraft_xml "radio" Radio.from_xml in
    let abs_telemetry_file, telemetry = get_config_element !gen_tl aircraft_xml "telemetry" Telemetry.from_xml in

    (* TODO extract/filter/resolve modules *)

    (* Generate output files *)
    let abs_airframe_h = aircraft_gen_dir // airframe_h in
    generate_config_element airframe
     (fun e -> Gen_airframe.generate e (value "ac_id") (get_string_opt !ac_name) "0x42" abs_airframe_file abs_airframe_h) (* TODO compute correct MD5SUM *)
     [ (abs_airframe_h, [abs_airframe_file]) ]; (* TODO add dep in included files *)

    let abs_radio_h = aircraft_gen_dir // radio_h in
    generate_config_element radio (fun e -> Gen_radio.generate e abs_radio_file abs_radio_h) [ (abs_radio_h, [abs_radio_file]) ];

    let abs_telemetry_h = aircraft_gen_dir // periodic_h in
    generate_config_element telemetry (fun e -> Gen_periodic.generate e !tl_freq abs_telemetry_h) [ (abs_telemetry_h, [abs_telemetry_file]) ];


(**
    let flight_plan_file = value "flight_plan" in
    let abs_flight_plan_file = paparazzi_conf // flight_plan_file in

    let target = try Sys.getenv "TARGET" with _ -> "" in
    let modules = Gen_common.get_modules_of_config ~target (value "ac_id") (ExtXml.parse_file abs_airframe_file) (ExtXml.parse_file abs_flight_plan_file) in
    (* normal settings *)
    let settings = try Env.filter_settings (value "settings") with _ -> "" in
    (* remove settings if not supported for the current target *)
    let settings = List.fold_left (fun l s -> if Gen_common.is_element_unselected ~verbose:true target modules s then l else l @ [s]) [] (Str.split (Str.regexp " ") settings) in
    (* update aircraft_xml *)
    let aircraft_xml = ExtXml.subst_attrib "settings" (Compat.bytes_concat " " settings) aircraft_xml in
    (* add modules settings *)
    let settings_modules = try Env.filter_settings (value "settings_modules") with _ -> "" in
    (* remove settings if not supported for the current target *)
    let settings_modules = List.fold_left (fun l s -> if Gen_common.is_element_unselected ~verbose:true target modules s then l else l @ [s]) [] (Str.split (Str.regexp " ") settings_modules) in
    (* update aircraft_xml *)
    let aircraft_xml = ExtXml.subst_attrib "settings_modules" (Compat.bytes_concat " " settings_modules) aircraft_xml in
    (* finally, concat all settings *)
    let settings = settings @ settings_modules in
    let settings = if List.length settings = 0 then
      begin
        fprintf stderr "\nInfo: No 'settings' attribute specified for A/C '%s', using 'settings/dummy.xml'\n\n%!" aircraft;
        "settings/dummy.xml"
      end
      else Compat.bytes_concat " " settings
    in

    (** Expands the configuration of the A/C into one single file *)
    let conf_aircraft = Env.expand_ac_xml aircraft_xml in
    let configuration =
      make_element
        "configuration" []
        [ make_element "conf" [] [conf_aircraft]; PprzLink.messages_xml () ] in
    let conf_aircraft_file = aircraft_conf_dir // "conf_aircraft.xml" in
    let f = open_out conf_aircraft_file in
    Printf.fprintf f "%s\n" (ExtXml.to_string_fmt configuration);
    close_out f;

    (** Computes and store a signature of the configuration *)
    let md5sum = Digest.to_hex (Digest.file conf_aircraft_file) in
    let md5sum_file = aircraft_conf_dir // "aircraft.md5" in
    (* Store only if different from previous one *)
    if not (Sys.file_exists md5sum_file
            && md5sum = input_line (open_in md5sum_file)) then begin
      let f = open_out md5sum_file in
      Printf.fprintf f "%s\n" md5sum;
      close_out f;

        (** Save the configuration for future use *)
      let d = U.localtime (U.gettimeofday ()) in
      let filename = sprintf "%02d_%02d_%02d__%02d_%02d_%02d_%s_%s.conf" (d.U.tm_year mod 100) (d.U.tm_mon+1) (d.U.tm_mday) (d.U.tm_hour) (d.U.tm_min) (d.U.tm_sec) md5sum aircraft in
      let d = Env.paparazzi_home // "var" // "conf" in
      mkdir d;
      let f = open_out (d // filename) in
      Printf.fprintf f "%s\n" (ExtXml.to_string_fmt configuration);
      close_out f end;

    let airframe_dir = Filename.dirname airframe_file in
    let var_airframe_dir = aircraft_conf_dir // airframe_dir in
    mkdir var_airframe_dir;
    assert (Sys.command (sprintf "cp %s %s" (paparazzi_conf // airframe_file) var_airframe_dir) = 0);

    (** Calls the Makefile with target and options *)
    let make = fun target options ->
      let c = sprintf "make -f Makefile.ac AIRCRAFT=%s AC_ID=%s AIRFRAME_XML=%s TELEMETRY=%s SETTINGS=\"%s\" MD5SUM=\"%s\" %s %s" aircraft (value "ac_id") airframe_file (value "telemetry") settings md5sum options target in
      begin (** Quiet is speficied in the Makefile *)
        try if Sys.getenv "Q" <> "@" then raise Not_found with
            Not_found -> prerr_endline c
      end;
      let returned_code = Sys.command c in
      if returned_code <> 0 then
        exit returned_code in

    (** Calls the makefile if the optional attribute is available *)
    let make_opt = fun target var attr ->
      try
        let value = Xml.attrib aircraft_xml attr in
        make target (sprintf "%s=%s" var value)
      with Xml.No_attribute _ -> () in

    let temp_makefile_ac = Filename.temp_file "Makefile.ac" "tmp" in

    let () = extract_makefile (value "ac_id") abs_airframe_file abs_flight_plan_file temp_makefile_ac in

    (* Create Makefile.ac only if needed *)
    let makefile_ac = aircraft_dir // "Makefile.ac" in
    if is_older makefile_ac (abs_airframe_file ::(List.map (fun m -> m.file) modules)) then
      assert(Sys.command (sprintf "mv %s %s" temp_makefile_ac makefile_ac) = 0);

    (* Get TARGET env, needed to build modules.h according to the target *)
    let t = try Printf.sprintf "TARGET=%s" (Sys.getenv "TARGET") with _ -> "" in
    (* Get FLIGHT_PLAN attribute, needed to build modules.h as well FIXME *)
    let t = t ^ try Printf.sprintf " FLIGHT_PLAN=%s" (Xml.attrib aircraft_xml "flight_plan") with _ -> "" in
    make_opt "radio_ac_h" "RADIO" "radio";
    make_opt "flight_plan_ac_h" "FLIGHT_PLAN" "flight_plan";
    make "all_ac_h" t
    *)
  with Failure f ->
    prerr_endline f;
    exit 1
