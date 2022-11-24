#!/usr/bin/perl -w
use File::Basename;

$ENV{'PATH'}.=':'.dirname($0);

system "unpack.pl";
system "convertpcb.pl";
system "convertschema.pl";

foreach my $fn(<*.PrjPcb>)
{
  my $pro=$fn; $pro=~s/\.PrjPcb/.kicad_pro/g;
  open OUT,">$pro";
  print OUT <<EOF
{
  "board": {
    "design_settings": {
      "defaults": {
        "board_outline_line_width": 0.1,
        "copper_line_width": 0.2,
        "copper_text_size_h": 1.5,
        "copper_text_size_v": 1.5,
        "copper_text_thickness": 0.3,
        "other_line_width": 0.15,
        "silk_line_width": 0.15,
        "silk_text_size_h": 1.0,
        "silk_text_size_v": 1.0,
        "silk_text_thickness": 0.15
      },
      "diff_pair_dimensions": [],
      "drc_exclusions": [],
      "rules": {
        "min_copper_edge_clearance": 0.0,
        "solder_mask_clearance": 0.0,
        "solder_mask_min_width": 0.0
      },
      "track_widths": [],
      "via_dimensions": []
    },
    "layer_presets": []
  },
  "boards": [],
  "cvpcb": {
    "equivalence_files": []
  },
  "libraries": {
    "pinned_footprint_libs": [],
    "pinned_symbol_libs": []
  },
  "meta": {
    "filename": "$pro",
    "version": 1
  },
  "net_settings": {
    "classes": [
      {
        "bus_width": 12.0,
        "clearance": 0.2,
        "diff_pair_gap": 0.25,
        "diff_pair_via_gap": 0.25,
        "diff_pair_width": 0.2,
        "line_style": 0,
        "microvia_diameter": 0.3,
        "microvia_drill": 0.1,
        "name": "Default",
        "pcb_color": "rgba(0, 0, 0, 0.000)",
        "schematic_color": "rgba(0, 0, 0, 0.000)",
        "track_width": 0.25,
        "via_diameter": 0.8,
        "via_drill": 0.4,
        "wire_width": 6.0
      }
    ],
    "meta": {
      "version": 2
    },
    "net_colors": null
  },
  "pcbnew": {
    "last_paths": {
      "gencad": "",
      "idf": "",
      "netlist": "",
      "specctra_dsn": "",
      "step": "",
      "vrml": ""
    },
    "page_layout_descr_file": ""
  },
  "schematic": {
    "legacy_lib_dir": "",
    "legacy_lib_list": []
  },
  "sheets": [],
  "text_variables": {}
}
EOF
  ;
  close OUT;
}
