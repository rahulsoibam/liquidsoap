(*****************************************************************************

  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2008 Savonet team

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

 *****************************************************************************)

open Lame_encoded

(** Output a MP3 stream to an icecast server *)

let no_mount = "Use [name]"
let no_name = "Use [mount]"

let proto =
  (Icecast2.proto ~no_mount ~no_name) @
  [ "samplerate", Lang.int_t, Some (Lang.int 44100), None;
    "bitrate", Lang.int_t, Some (Lang.int 128), None;
    "quality", Lang.int_t, Some (Lang.int 5), None;
    "stereo", Lang.bool_t, Some (Lang.bool true), None;
    "start", Lang.bool_t, Some (Lang.bool true),
    Some "Start output threads on operator initialization." ;
    "", Lang.source_t, None, None ]

let no_multicast = "no_multicast"

class to_shout p =
  let e f v = f (List.assoc v p) in
  let s v = e Lang.to_string v in

  let stereo = e Lang.to_bool "stereo" in
  let samplerate = e Lang.to_int "samplerate" in
  let bitrate = e Lang.to_int "bitrate" in
  let quality = e Lang.to_int "quality" in

  let source = List.assoc "" p in
  let autostart = Lang.to_bool (List.assoc "start" p) in
  let mount = s "mount" in
  let name = s "name" in
  let name =
    if name = no_name then
      if mount = no_mount then
        raise (Lang.Invalid_value
                 ((List.assoc "mount" p),
                  "Either name or mount must be defined."))
      else
        mount
    else
      name
  in
  let mount =
    if mount = no_mount then name else mount
  in
  let protocol =
    let v = List.assoc "protocol" p in
      match Lang.to_string v with
        | "http" -> Shout.Protocol_http
        | "icy" -> Shout.Protocol_icy
        | _ ->
            raise (Lang.Invalid_value
                     (v, "valid values are 'http' (icecast) "^
                      "and 'icy' (shoutcast)"))
  in
  let channels =
    if not stereo then 1 else Fmt.channels ()
  in
  let icecast_info =
    {
     Icecast2.
      quality    = None;
      bitrate    = Some bitrate;
      channels   = Some channels;
      samplerate = Some samplerate
    }
  in
object (self)
  inherit
    [Lame.encoder] Output.encoded ~autostart ~name:mount ~kind:"output.icecast" source
  inherit
    Icecast2.output ~format:Shout.Format_mp3 ~protocol
      ~icecast_info ~mount ~name ~source p as icecast
  inherit base ~quality ~bitrate ~stereo ~samplerate as base

  method reset_encoder m =
    let get h k l =
      try
        (k,(Hashtbl.find h k))::l
      with _ -> l
    in
    let getd h k d l =
      try
        (k,(Hashtbl.find h k))::l
      with _ -> (k,d)::l
    in
    let def_title =
      match get m "uri" [] with
        | (_,s)::_ -> let title = Filename.basename s in
            ( try
                String.sub title 0 (String.rindex title '.')
              with
                | Not_found -> title )
        | [] -> "Unknown"
    in
    let song =
      try
        Hashtbl.find m "song"
      with _ ->
        (try
          (Hashtbl.find m "artist") ^ " - "
        with _ -> "")
        ^
        (try
          Hashtbl.find m "title"
        with _ -> "Unknown")
    in
    let a = Array.of_list
      (getd m "title" def_title
         (get m "artist"
            (get m "genre"
               (get m "date"
                  (get m "album"
                     (get m "tracknum"
                        (get m "comment"
                          (getd m "song" song [])))))))) (* for Shoutcast *)
    in
      match connection with
        | Some c ->
            (try Shout.set_metadata c a ; "" with _ -> "")
        (* Do nothing if shout connection isn't available *)
        | None -> ""

  method output_start =
    icecast#icecast_start ;
    base#output_start 

  method output_stop = icecast#icecast_stop

  method output_reset = 
    self#output_stop;
    self#output_start

end

let () =
    Lang.add_operator "output.icecast.mp3" ~category:Lang.Output
      ~descr:
  "Output the source's stream to an icecast2 compatible server in MP3 format."
      proto
      (fun p -> ((new to_shout p):>Source.source))

