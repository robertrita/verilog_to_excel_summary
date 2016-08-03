#!/usr/bin/perl


use strict;
use Getopt::Long;
use File::Path;
use Data::Dumper;


######################################################################
# DEFINE GLOBAL VARS
######################################################################
my $script = 'audit_connection.pl';
my $rev = '0.1';

my %opt;
my %f;
my $DEBUG;
my $module;
my $keysheet;
my $output;
my $date = `date`; chomp($date);
my $user = `echo \$USER`; chomp($user);
my $bound = '---------------------------------------------------------------';

my $logheader = <<"EOF";
########################################################################
# GENERIC CONNECTION FILE AUDIT TOOL
# Log file generated by $script revision $rev.
#
# USER: $user
# DATE: $date
########################################################################
EOF

ECHO($logheader);
ECHO($bound);

Getopt::Long::config ("no_auto_abbrev","no_pass_through");
if (! GetOptions (
                  "dir=s"		=> \$opt{dir},
                  "excel=s"		=> \$opt{excel},
                  "xfilter=s"		=> \$opt{xfilter},
                  "v=s"			=> \$opt{verilog},
                  "module=s"		=> \$opt{module},
                  "sheet=s"		=> \$opt{sheet},
                  "show=s"		=> \$opt{show},
                  "ip=s"		=> \$opt{ip},
                  "int=s"		=> \$opt{int},
                  "audit=s"		=> \$opt{audit},
                  "ipvsint"		=> \$opt{ipvsint},
                  "update"		=> \$opt{update},
                  "h|help"		=> \&USAGE,
                  "<>"			=> \&PARAMETER,
                  )) { ERROR('[ERROR 0a]Invalid parameter') }


######################################################################
# MAIN
######################################################################

MAIN();
exit(0);


######################################################################
# SUB MAIN
######################################################################

#CREATE AND POPULATE PWR WORKAREA DIR...
sub MAIN {

my ($ext, $vref, $xlref, $xlrangeref, $xlportsref);
my $verilogfile = $opt{verilog};
my $excelfile = $opt{excel};
my $xfilter = "conn";
my $dir;
	
	if ($opt{module}) {$module = $opt{module}}
	if ($opt{xfilter}) {$xfilter = $opt{xfilter}}
	
	if ($opt{dir}) {$dir = $opt{dir}; chdir($dir)}
	else {$dir = `pwd`; chomp($dir)}
	
	if ($dir =~ /.*\/custom_design\/\S+\/common_data\/conn$/i) {	#for CUSTOM DESIGN COMMON_DATA
		if (!$module) {ERROR("PLEASE USE -module OPTION FOR COMMON_DATA")};
		if (!$excelfile) {$excelfile = `ls | grep .xls | grep $xfilter | head -1`; chomp($excelfile); $excelfile = "$dir/$excelfile"}
		if (!$verilogfile) {$verilogfile = "../../$module/netlists/verilog_func/$module.v"; $verilogfile = "$dir/$verilogfile"}
	}
	elsif ($dir =~ /.*\/custom_design\/\S+\/(\S+)\/conn$/i) {	#for CUSTOM DESIGN
		$module = $1 if (!$module);
		if (!$excelfile) {$excelfile = `ls | grep .xls | grep $xfilter | head -1`; chomp($excelfile); $excelfile = "$dir/$excelfile"}
		if (!$verilogfile) {$verilogfile = "../netlists/verilog_func/$module.v"; $verilogfile = "$dir/$verilogfile"}
	}
	elsif ($dir =~ /.*\/logic_design\/(\S+)\/data\/conn$/i) {	#for LOGIC DESIGN and IP GENERIC
		$module = $1 if (!$module);
		if (!$excelfile) {$excelfile = `ls | grep .xls | grep $xfilter | head -1`; chomp($excelfile); $excelfile = "$dir/$excelfile"}
		if (!$verilogfile) {$verilogfile = "../netlists/verilog_func/$module.v"; $verilogfile = "$dir/$verilogfile"}
	}
	elsif (($verilogfile)&&($excelfile)) { if (!$module) {ERROR("PLEASE DEFINE -module OPTION")} }
	else {ERROR("YOU ARE NOT IN THE conn/ DIRECTORY, PLEASE PROVIDE -dir OPTION")}
	
	$output = "$dir/new_connection_file_$module.xlsx";
	
 	if ($verilogfile) {
		print "VERILOG FILE USED : $verilogfile\n";
		if (!-e $verilogfile) {ERROR("VERILOG FILE NOT FOUND : $verilogfile")}		
		$vref = PARSE_VERILOG($verilogfile);
	}
		
	if ($excelfile) {
		print "EXCEL FILE USED : $excelfile\n\n";
		if (!-e $excelfile) {ERROR("EXCEL FILE NOT FOUND : $excelfile")}
		if ($excelfile =~ /\S+\.(\w+)$/i) {$ext = $1}
		
		if ($ext eq 'xlsx') { ($xlref,$xlrangeref) = PARSE_XLSX($excelfile) }
		else { ($xlref,$xlrangeref) = PARSE_XLS($excelfile) }
		$xlportsref = GET_XLPORTS($xlref,$xlrangeref);
	}
	
	COMPARE_V($vref,$xlportsref);
	if ($opt{ipvsint}) {COMPARE_X($xlportsref)}
	
	if ($opt{update}) { UPDATE_XLSX($xlref) }
	
return;
}

######################################################################
# GET VERILOG PORT DATA

sub PARSE_VERILOG {

use Verilog::Netlist;
use Verilog::Getopt;
my $verilogfile = shift;
my $i=0;
my %v;

        my $opt = new Verilog::Getopt;
        $opt->parameter( "+incdir+verilog","-y","verilog");

        # Prepare netlist
        my $nl = new Verilog::Netlist (options => $opt, link_read_nonfatal => 1);

        $nl->read_file (filename=>$verilogfile);

        # Read in any sub-modules
        $nl->link();
        #$nl->lint();  # Optional, see docs; probably not wanted
        #$nl->exit_if_error();
	
        for my $mod ($nl->modules) {
        my $modname = $mod->name;                                               DUMPER($modname) if($DEBUG eq '2a');
                if ($modname =~ /^$module$/i) {
			$f{modname} = 1;
                        for my $sig ($mod->ports_sorted) {
				my ($port, $type) = ($sig->name, $sig->direction);
                                $v{port}[$i] = $port;
                                $v{$port}{type} = $type;
                                $i++;
                        }
                }
        }
	if (!$f{modname}) {ERROR("CAN'T FIND MODULE : \"$module\"")}
	#DUMPER(\%v);


return (\%v);
}

######################################################################
# GET EXCEL PORT DATA

sub PARSE_XLSX {

use Spreadsheet::XLSX;
my $excelfile = shift;
my $port;
my $type;
my $c=0;
my $i=0;
my %xlrange;
my %xl;

        my $excel = Spreadsheet::XLSX -> new ($excelfile) || ERROR("[ERROR 2a]Can't find $1...");
	
        for my $sheet (@{$excel -> {Worksheet}}) {
		my $sheetname = $sheet->{Name};
		
                for my $row ($sheet -> {MinRow} .. $sheet -> {MaxRow}) {
			if (!$xlrange{$sheetname}{row}) {$xlrange{$sheetname}{row} = $sheet -> {MaxRow}}
			
                        for my $col ($sheet -> {MinCol} ..  $sheet -> {MaxCol}) {
				if (!$xlrange{$sheetname}{col}) {$xlrange{$sheetname}{col} = $sheet -> {MaxCol}}
                                my $cell = $sheet -> {Cells} [$row] [$col];
				my $val;
				if (!$cell) {$val = ""}
				else {$val = $cell -> {Val}}
				for ($val) {s/&lt;/</ig; s/&gt;/>/ig}
				for ($val) {s/\[/</ig; s/\]/>/ig}
				
                                $xl{$sheetname}[$col][$row] = $val;
                        }
                }
        }
	#DUMPER(\%xl);


return (\%xl,\%xlrange);
}

######################################################################
# GET EXCEL PORT DATA

sub PARSE_XLS {

use Spreadsheet::ParseExcel;
my $excelfile = shift;
my $port;
my $type;
my $c=0;
my $i=0;
my %xlrange;
my %xl;
	
	my $parser   = Spreadsheet::ParseExcel->new();
	my $workbook = $parser->parse($excelfile);
	
	if ( !defined $workbook ) { die $parser->error(), ".\n" }
	for my $worksheet ( $workbook->worksheets() ) {
		my $sheetname = $worksheet->get_name();
		my ( $row_min, $row_max ) = $worksheet->row_range();
		my ( $col_min, $col_max ) = $worksheet->col_range();
		
		for my $row ( $row_min .. $row_max ) {
			if (!$xlrange{$sheetname}{row}) {$xlrange{$sheetname}{row} = $row_max}
		
			for my $col ( $col_min .. $col_max ) {
				if (!$xlrange{$sheetname}{col}) {$xlrange{$sheetname}{col} = $col_max}
				my $cell = $worksheet->get_cell( $row, $col );
				my $val;
				if (!$cell) {$val = ""}
				else {$val = $cell->value()}
				for ($val) {s/&lt;/</ig; s/&gt;/>/ig}
				for ($val) {s/\[/</ig; s/\]/>/ig}
				
				$xl{$sheetname}[$col][$row] = $val;
			}
		}
	}
	#DUMPER(\%xl);
	#DUMPER(\%xlrange);


return (\%xl,\%xlrange);
}

######################################################################
# GET EXCEL PORT DATA

sub GET_XLPORTS {

my ($xlref, $xlrangeref) = @_;
my %xl = %{$xlref};
my %xlrange = %{$xlrangeref};
my %xlports;
my @excelsheet;
my $sheetname;
	
	if ($opt{ipvsint}) {
		if (!$opt{ip}) {$opt{ip} = "IP Information"}
		if (!$opt{int}) {$opt{int} = "Integration Connectivity"}
		@excelsheet = ($opt{ip}, $opt{int});
	}
	else {
		if ($opt{sheet}) {$sheetname = $opt{sheet}}
		elsif ($opt{module}) {$sheetname = $opt{module}}
		else {$sheetname = "ip"}
		@excelsheet = $sheetname;
	}
											#DUMPER(\%xlrange);
	if ($opt{show} =~ /^sheet/i) {
		my @list = keys %xl;
		print "EXCEL SHEETS :\n";
		for (@list) {print "\t\"$_\"\n"}
		return;
	}
	elsif ($opt{show}) {ERROR("NEED CORRECT ARGUMENTS FOR -show")}
	
	for my $sheetname (@excelsheet) {
	my $key;
	my $port;
	my $type;
	    for my$k (keys %xl) {
		if ($k =~ /^$sheetname/i) {						#DUMPER($k);
			$key = $k;
			my $c=0;
			my $i=0;
			for my$row (0 .. $xlrange{$key}{row}) {
				my ($port0, $portname);
				for my$col (0 .. $xlrange{$key}{col}) {
					my $val = $xl{$key}[$col][$row];		#DUMPER("$val : $col : $row");
					if ((!$port)&&($val =~ /^port$/i)) {$port=$col}
					elsif ((!$type)&&($val =~ /^port\s+type/i)) {$type=$col}
					elsif ((!$type)&&($val =~ /^\s*i\/o\s*/i)) {$type=$col}
					elsif ((!$port)&&(!$type)) { next }
					elsif ($val) {					#values were parsed in port and port type columns only
						if ($val =~ /\S+\s+\S+.*/i) { next }
						elsif ($val =~ /note\s*:/i) { next }
						elsif ($val =~ /[a-z]+\s*:\s*[a-z]+/i) { next }
						
						if ($col==$port) {
							$port0 = $val;
							$portname = $val;
							for ($portname) {s/\*/\.\*/ig; s/\<A0\>//ig}
							if ($portname =~ /\s*(\S+)\s*/i) {$portname = $1}
							if ($portname =~ /(\S+)\<\S+\>/i) {$portname = $1}
							
							if ($portname =~ /.*\S+\/\S+$/i) {
								my @ports = split("/", $portname);
								my $name = shift@ports;
								$xlports{$key}{port}[$c] = $name; $c++;
								
								if ($name =~ /(\S+\_)[a-z]+$/i) {$name = $1}
								for (@ports) {
									$portname = "$name$_";
									$xlports{$key}{port}[$c] = $portname; $c++;
								}
							}
							elsif ($portname =~ /.*\S+\,\s*\S+$/i) {
								my @list = split(",", $portname);
								my $base;
								for my$portname (@list) {
									if ($portname =~ /^(\w+)\d\d\d\d$/i) {$base = $1}
									elsif ($portname =~ /^(\w+\.\*)\d\d$/i) {$base = $1}
									else {$portname = "$base$portname"}
									$xlports{$key}{port}[$c] = $portname; $c++;
								}
							}
							else {
								$xlports{$key}{port}[$c] = $portname; $c++;
							}
						}
						elsif (($col==$type)&&($portname)) {
							for ($val) {s/i/in/ig; s/o/out/ig; s/p/power/ig; s/\///g}
							
							$portname = $port0;
							for ($portname) {s/\*/\.\*/ig; s/\<A0\>//ig}
							if ($portname =~ /\s*(\S+)\s*/i) {$portname = $1}
							if ($portname =~ /(\S+)\<\S+\>/i) {$portname = $1}
							
							if ($portname =~ /.*\S+\/\S+$/i) {
								my @ports = split("/", $portname);
								my $name = shift@ports;
								$xlports{$key}{$name}{type} = $val;
								
								if ($name =~ /(\S+\_)[a-z]+$/i) {$name = $1}
								for (@ports) {
									$portname = "$name$_";
									$xlports{$key}{$portname}{type} = $val;
								}
							}
							elsif ($portname =~ /.*\S+\,\s*\S+$/i) {
								my @list = split(",", $portname);
								my $base;
								for my$portname (@list) {
									if ($portname =~ /^(\w+)\d\d\d\d$/i) {$base = $1}
									elsif ($portname =~ /^(\w+\.\*)\d\d$/i) {$base = $1}
									else {$portname = "$base$portname"}
									$xlports{$key}{$portname}{type} = $val;
								}
							}
							else {$xlports{$key}{$portname}{type} = $val}
						}
						else { next }
                                	}
                                	else { next }
				}
			}
			if ((!$port)&&($opt{audit} =~ /port/i)) {ERROR("PORT COLUMN IS NOT DEFINED")}
			elsif ((!$type)&&($opt{audit} =~ /type/i)) {ERROR("PORT TYPE COLUMN IS NOT DEFINED")}
		}
	    }
	    if (!$key) {ERROR("CAN'T FIND SHEET : \"$sheetname\"")}
	}
	#DUMPER(\%xlports);

return (\%xlports);
}

######################################################################
# GET EXCEL PORT DATA

sub COMPARE_V {

my($vref,$xlportsref) = @_;
my %v = %{$vref};
my %xlports = %{$xlportsref};
my %match;
my $key;

	ECHO("$bound\nCHECKING VERILOG VS EXCEL\n$bound\n");
	if (!$opt{audit}) {$opt{audit} = "port and type"}
	
	if ($opt{ipvsint}) { $key = $opt{ip} }
	else { for (keys %xlports) { $key = $_; last } }
	
	my $x=0;
	my $y=0;
	for my$c (0 .. $#{$v{port}}) {
		my $portv = $v{port}[$c];
		my $typev = $v{$portv}{type};
		
		for my$i (0 .. $#{$xlports{$key}{port}}) {
			my $portx = $xlports{$key}{port}[$i];
			my $typex = $xlports{$key}{$portx}{type};
			
			if ($portv =~ /^$portx$/i) {
				$match{portv}[$c] = $portv; 			#DUMPER("$typev : $typex");
				if ($typev =~ /^$typex$/i) {$match{typev}[$c] = $typev}
			}
		}
		if (!$match{portv}[$c]) {$match{diff}{portv}[$x] = $portv; $x++}
		if (!$match{typev}[$c]) {$match{diff}{typev}[$y] = "$portv : $typev"; $y++}
	}
	
	if ($opt{audit} =~ /port/i) {
		print "MISMATCH PORTS in VERILOG, \"$module\" : ";
		if (!$match{diff}{portv}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{portv})}
		print "\n";
	}
	if ($opt{audit} =~ /type/i) {
		print "MISMATCH PORT TYPE in VERILOG, \"$module\" : ";
		if (!$match{diff}{typev}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{typev})}
		print "\n";
	}
	
	
	my $x=0;
	my $y=0;
	for my$i (0 .. $#{$xlports{$key}{port}}) {
		my $portx = $xlports{$key}{port}[$i];
		my $typex = $xlports{$key}{$portx}{type};
		
		for my$c (0 .. $#{$v{port}}) {
			my $portv = $v{port}[$c];
			my $typev = $v{$portv}{type};
			
			if ($portx =~ /^$portv$/i) {
				$match{portx}[$i] = $portx; 			#DUMPER("$typex : $typev");
				if ($typex =~ /^$typev$/i) {$match{typex}[$i] = $typex}
			}
		}
		if (!$match{portx}[$i]) {$match{diff}{portx}[$x] = $portx; $x++}
		if (!$match{typex}[$i]) {$match{diff}{typex}[$y] = "$portx : $typex"; $y++}
	}
	
	if ($opt{audit} =~ /port/i) {
		print "MISMATCH PORTS in EXCEL, \"$key\" : ";
		if (!$match{diff}{portx}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{portx})}
		print "\n";
	}
	if ($opt{audit} =~ /type/i) {
		print "MISMATCH PORT TYPE in EXCEL, \"$key\" : ";
		if (!$match{diff}{typex}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{typex})}
		print "\n";
	}
return;
}

######################################################################
# GET EXCEL PORT DATA

sub COMPARE_X {

my $xlportsref = shift;
my %xlports = %{$xlportsref};
my %match;
my $key;

	ECHO("$bound\nCHECKING IP VS INT\n$bound\n");
	if (!$opt{audit}) {$opt{audit} = "port and type"}
	my $ip = $opt{ip};
	my $int = $opt{int};

	my $x=0;
	my $y=0;
	for my$c (0 .. $#{$xlports{$ip}{port}}) {
		my $portv = $xlports{$ip}{port}[$c];
		my $typev = $xlports{$ip}{$portv}{type};
		
		my $portx = $xlports{$int}{port}[$c];
		my $typex = $xlports{$int}{$portx}{type};
			
		if ($portv =~ /^$portx$/i) {
			$match{portv}[$c] = $portv; 			#DUMPER("$typev : $typex");
			if ($typev =~ /^$typex$/i) {$match{typev}[$c] = $typev}
		}
		if (!$match{portv}[$c]) {$match{diff}{portv}[$x] = "\[port:$c\]$portv"; $x++}
		if (!$match{typev}[$c]) {$match{diff}{typev}[$y] = "$portv : $typev"; $y++}
	}
	
	if ($opt{audit} =~ /port/i) {
		print "MISMATCH PORTS in IP, \"$ip\" : ";
		if (!$match{diff}{portv}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{portv})}
		print "\n";
	}
	if ($opt{audit} =~ /type/i) {
		print "MISMATCH PORT TYPE in IP, \"$ip\" : ";
		if (!$match{diff}{typev}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{typev})}
		print "\n";
	}
	
	
	my $x=0;
	my $y=0;
	for my$i (0 .. $#{$xlports{$int}{port}}) {
		my $portx = $xlports{$int}{port}[$i];
		my $typex = $xlports{$int}{$portx}{type};
		
		my $portv = $xlports{$ip}{port}[$i];
		my $typev = $xlports{$ip}{$portx}{type};
			
		if ($portx =~ /^$portv$/i) {
			$match{portx}[$i] = $portx; 			#DUMPER("$typex : $typev");
			if ($typex =~ /^$typev$/i) {$match{typex}[$i] = $typex}
		}
		if (!$match{portx}[$i]) {$match{diff}{portx}[$x] = "\[port:$i\]$portx"; $x++}
		if (!$match{typex}[$i]) {$match{diff}{typex}[$y] = "$portx : $typex"; $y++}
	}
	
	if ($opt{audit} =~ /port/i) {
		print "MISMATCH PORTS in INT, \"$int\" : ";
		if (!$match{diff}{portx}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{portx})}
		print "\n";
	}
	if ($opt{audit} =~ /type/i) {
		print "MISMATCH PORT TYPE in INT, \"$int\" : ";
		if (!$match{diff}{typex}) {print "yehey! no difference\n"}
		else {print "\n"; DUMPER($match{diff}{typex})}
		print "\n";
	}
return;
}

######################################################################
# GET EXCEL PORT DATA
sub UPDATE_XLSX {

use Excel::Writer::XLSX;

my $xlref = shift;
my %xl = %{$xlref};
	
	unlink($output);
        my $workbook  = Excel::Writer::XLSX->new( "$output" );
	
	for my$key (keys %xl) {
		my $worksheet = $workbook->add_worksheet($key);
		$worksheet->set_column(0, 50, 25);
		$worksheet->write( 'A1', $xl{$key} );
	}
	
	print "UPDATED CONN FILE :\n\t $output\n\n";

return;
}

















#=====================================================================
#=====================================================================
# UTILITY MODULES
#=====================================================================
#=====================================================================

######################################################################
# ERROR

sub ERROR {
	my $error = shift;
	print STDOUT "%Error: $error, try \'$script --help\'\n\n";
	
	exit (1);
}

######################################################################
# DEBUGGER

sub DEBUGGER { print STDOUT "@_\n"; return }

######################################################################
# DUMPER

sub DUMPER { print Dumper @_; return }

######################################################################
# ECHO

sub ECHO { print STDOUT "@_\n"; return }

######################################################################
# LOG

sub LOG { print LOG "@_\n"; return }

######################################################################
# WRONG OPTION

sub PARAMETER {
	my $param = shift;
	if ($param =~ /^--?/) {	die "Unknown parameter: $param\n" }	#filter out correct options
	else { return }							# Must quote to convert Getopt to string
return;
}


######################################################################
######################################################################
######################################################################
######################################################################

# HELP

sub USAGE {
my $tool = "make_conn_comp.pl";
my $snowv1 = "/home/rrita/windows/conn/snow/ebr.v";
my $snowx1 = "/home/rrita/windows/conn/snow/connection_file_ebr.xlsx";
my $snowd2 = "/lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_ioslm/common_data/conn";
my $snowv2 = "../../ioslm_allblocks/netlists/verilog_func/ioslm_allblocks.v";
my $snowd3 = "/lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_piclm/common_data/conn";

print <<EOH;
--------------------------------------------------------------------------------------------------------
DESCRIPTION
	$script - A tool that create, audit and update connection file.

USAGE
	$script <dir> [option]

OPTION
	Required:
	<dir> 						This is the conn/ directory in your workarea

	Optional:
	-excel	<.xlsx or .xls conn file>		connection file as input
	-v	<verilog file>				verilog file as input
	-module	<verilog module name>			module name in the verilog file
	-sheet	<excel sheet name>			sheet name in the connection file
	-show	<sheet>					aids to show a preview of sheet names
	-audit	<port|type>				enables audit preference
	-update						enables connection file update based from the verilog file reference
	-h|help						display help

EXAMPLES
	 ##sample1 : invoked tool without arguments, automatically search for excel and verilog files in PWD
	  cd /lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_ebr_9kb/ebr/conn
	  $tool
	 
	 ##sample2 : with -dir argument, automatically search for excel and verilog files
	  $tool -dir /lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_ebr_9kb/ebr/conn
	 
	 ##sample3 : will accept hard input excel file while verilog remains automatically searched
	  cd /lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_ebr_9kb/ebr/conn
	  $tool -excel $snowx1
	 
	 ##sample4 : user may opt to specify which excelsheet to use
	  cd /lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_ebr_9kb/ebr/conn
	  $tool -excel $snowx1 -sheet "Integration Connectivity"
	 
	 ##sample5 : will accept hard input verilog file while excel remains automatically searched
	  cd /lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_ebr_9kb/ebr/conn
	  $tool -v $snowv1
	 
	 ##sample6 : will accept hard input excel and verilog files but needs to indicate which module
	  $tool -v $snowv1 -excel $snowx1 -module ebr -sheet "IP Information"
	 
	 ##sample7 : able to handle common_data dir which requires module name, sheet name is optional
	  $tool -dir $snowd2 -v $snowv2 -module ioslm_bankref_t -sheet "ioslm_bankref_t INFO"
	 
	 ##sample8 : use -show "sheet" if you want to know the sheetnames available but then again -module is required for common_data
	  $tool -dir $snowd3 -show sheet -module piclm_g
	 
	 ##sample9 : handles common_data with -module and -sheet were indicated
	  $tool -dir $snowd3 -module piclm_g -sheet "piclm_g INFO"
	 
	 ##sample10 : handles especial port naming case in piclm_l4
	  $tool -dir $snowd3 -module piclm_l4 -sheet "piclm_l4 INFO"
	 
	 ##sample11 : create updated .xlsx file
	  cd /lsc/projects/IP/ip_umc40lp_9M2T1H0A1U_mdkfdk_ver01/rrita/workarea/custom_design/umc40lp_ebr_9kb/ebr/conn
	  $tool -run update

SCOPE AND LIMITATIONS
	1. Supports connection file audit for different projects and different directories.

REVISION HISTORY:
	1. 11/18/15[rrita] -initial version
--------------------------------------------------------------------------------------------------------
EOH
exit(1);
}

__END__

