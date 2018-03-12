(*
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
 * Flight_plan module for parsing XML config files
 *)

module OT = Ocaml_tools

let parse_children_attribs = fun tag f children ->
  List.fold_left (fun l x -> if Xml.tag x = tag then f (Xml.attribs x) :: l else l)
  [] children

module Module_fp = struct

  type t = { name: string;
             mtype: string option;
             configures: Module.configure list;
             defines: Module.define list;
             xml: Xml.xml }

  let from_xml = function
    | Xml.Element ("module", attrs, children) as xml ->
        { name = List.assoc "name" attrs;
          mtype = OT.assoc_opt "type" attrs;
          configures = parse_children_attribs "configure" Module.parse_configure children;
          defines = parse_children_attribs "define" Module.parse_define children;
          xml }
    | _ -> failwith "Airframe.Module_af.from_xml: unreachable"

end

type t = {
  filename: string;
  settings: Settings.Dl_setting.t list;
  modules: Module_fp.t list;
  xml: Xml.xml;
}

let from_xml = function
  | Xml.Element ("flight_plan", _, children) as xml ->
      let settings = List.fold_left (fun s el ->
        if Xml.tag el = "variables" then
          s @ List.fold_left (fun s e -> 
            if Xml.tag el = "variable" then
              let attribs = Xml.attribs e in
              let test attrib = List.mem_assoc attrib attribs in
              let get_opt attrib = try Some (List.assoc attrib attribs) with _ -> None in
              if test "min" && test "max" && test "step" then
                [{
                  Settings.Dl_setting.var = List.assoc "var" attribs;
                  shortname = get_opt "shortname";
                  handler = None;
                  header = None;
                  xml = Xml.Element ("dl_setting", attribs, []);
                }] @ s
              else
                s
            else
              s
          ) [] (Xml.children el)
        else
          s
      ) [] children in
      let modules = List.fold_left (fun m el ->
        if Xml.tag el = "modules" then
          m @ List.map Module_fp.from_xml (Xml.children el)
        else
          m
      ) [] children in
      { filename = ""; settings; modules; xml }
  | _ -> failwith "Flight_plan.from_xml: unreachable"

let from_file = fun filename ->
  let fp = from_xml (Xml.parse_file filename) in
  { fp with filename }