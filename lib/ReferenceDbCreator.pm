package ReferenceDbCreator;

use Log::Log4perl qw(:no_extra_logdie_message);
use File::Path qw(make_path);
use NCBI::Taxonomy;
use FindBin;

our $VERSION = '0.0.1';

my $L = Log::Log4perl::get_logger();

sub new {
	my $class = shift;
	my $object = shift;
	bless $object, $class;
    $object->create_outdir_if_not_exists();
	# init a root logger in exec mode
	Log::Log4perl->init(
	\q(
                log4perl.rootLogger                     = DEBUG, Screen, FileApp
				log4perl.appender.FileApp				= Log::Log4perl::Appender::File
				log4perl.appender.FileApp.filename		= sub{ logfile() }
				log4perl.appender.FileApp.layout		= PatternLayout
				log4perl.appender.FileApp.layout.ConversionPattern = [%d{MM-dd HH:mm:ss}] [%C] %m%n
                log4perl.appender.Screen                = Log::Log4perl::Appender::Screen
                log4perl.appender.Screen.stderr         = 1
                log4perl.appender.Screen.layout         = PatternLayout
                log4perl.appender.Screen.layout.ConversionPattern = [%d{MM-dd HH:mm:ss}] [%C] %m%n
        )
	);
	return $object;
}

sub create_outdir_if_not_exists{
	my $self = shift;
	my $outdir = $self->{outdir};
	make_path($outdir, {error => \my $err});
	if (@$err)
	{
	    for my $diag (@$err) {
			my ($file, $message) = %$diag;
			# Just die instead of logdie here as the logger is not initialized when first called.
			# Set exit code to 1 explicitly - otherwise not predictable (or testable)
			$! = 1;
			if ($file eq '') {
				die("Creating folder failed with general error: $message");
			}
			else {
				die("Creating folder failed for folder '$file': $message");
			}
	    }
	}
}

sub search_ncbi{
	my $self = shift;
	my $outdir = $self->{outdir};
	my $search_term = $self->{marker_search_string};
	my $edirect_dir = $self->{edirect_dir};
	my $full_search_string = "($search_term)";
	# add taxonomic range
	my $taxonomic_range = $self->{taxonomic_range};
	$full_search_string .= " AND $taxonomic_range\[ORGN]" if($taxonomic_range);
	# add taxon list (empty string if taxa file not given or empty)
	$full_search_string .= $self->get_taxa_filter_string_from_taxfile();
	# add seq length range
	my $seqlen_filter = $self->{sequence_length_filter};
	$full_search_string .= " AND $seqlen_filter\[SLEN]" if($seqlen_filter);
	# exclud EST and GSS data
	$full_search_string .= " NOT gbdiv est[prop] NOT gbdiv gss[prop]";
	$L->info("Full search string: ".$full_search_string);
	my $cmd = $edirect_dir."esearch -db nuccore -query \"$full_search_string\" | ".$edirect_dir."efetch -format docsum | ".$edirect_dir."xtract -pattern DocumentSummary -element Caption,TaxId,Slen > $outdir/list.txt";
	$self->run_command($cmd, "Run search against NCBI");
}

sub limit_seqs_per_taxon{
	my $self = shift;
	my $outdir = $self->{outdir};
	my $seqs_per_taxon = $self->{seqs_per_taxon};

	# get number of results
	my $cmd = "sort -k2,2 -k 3,3nr $outdir/list.txt > $outdir/list.sorted.txt";
	$self->run_command($cmd, "Sort sequence list by taxon and length");

	$L->info("Filtering number of sequences per taxon by --sequences-per-taxon ($seqs_per_taxon) into $outdir/list.filtered.txt");
	open(IN, "<$outdir/list.sorted.txt") or die "Can not open file $outdir/list.sorted.txt $!";
	open(OUT, ">$outdir/list.filtered.txt") or die "Can not open file $outdir/list.filtered.txt $!";
	my $last_taxid = "xxx";
	my $taxid_count = 0;
	while(<IN>){
		chomp;
		my ($acc, $taxid, $len) = split(/\t/);
		if($taxid eq $last_taxid){
			$taxid_count++;
		} else {
			$taxid_count = 0;
		}
		$last_taxid = $taxid;
		if($taxid_count < $seqs_per_taxon){
			print OUT "$acc\t$taxid\n";
		}
	}
	close(OUT) or die "Can not close file $outdir/list.filtered.txt $!";
	close(IN) or die "Can not close file $outdir/list.sorted.txt $!";
	$L->info("Finished filtering sequence list");
}

sub download_sequences{
	my $self = shift;
	my $outdir = $self->{outdir};
	my $batch_size = $self->{edirect_batch_size};
	my $edirect_dir = $self->{edirect_dir};
	my $efetch_bin = $edirect_dir."efetch";
	my $epost_bin = $edirect_dir."epost";

	# get number of results
	my $num_results = qx(wc -l $outdir/list.filtered.txt);
	$L->info("Number of search results: $num_results");

	# clear sequence file (might exist from previous incomplete run)
	$L->info("Removing $outdir/sequences.fa if it exists");
	if ( -e $outdir."/sequences.fa" ) {
        unlink($outdir."/sequences.fa") or $L->logdie("$!");
    }
	
	$L->info("Now downloading sequences in batches of $batch_size");
	for(my $i=1; $i<=$num_results; $i+=$batch_size){
		my $msg = "Downloading fasta sequences for batch: $i - ".($i+$batch_size-1);
		my $cmd = "tail -n+$i $outdir/list.filtered.txt | head -n $batch_size | cut -f1 | $epost_bin -db nuccore | $efetch_bin -format fasta >>$outdir/sequences.fa";
		$self->run_command($cmd, $msg);
	}
	$L->info("Finished downloading sequences");
}

sub filter_and_orient_by_primers{
	my $self = shift;
	my $outdir = $self->{outdir};
	my $primer_file = $self->{primer_file};
	return unless($primer_file);
	# filter/crop
	my $dispr_bin = $self->{dispr_bin};
	my $msg = "Get products of in silico pcr with provided degenerate primers: $primer_file";
	my $rawoutfile = "$outdir/sequences.dispr.raw.fa";
	my $cmd = "$dispr_bin --primers $primer_file --ref $outdir/sequences.tax.fa --seq $rawoutfile";
	$self->run_command($cmd, $msg);
	# fix orientation
	$self->run_command("sed -i 's/,/_/' $rawoutfile", "Replace problematic ',' in fasta header with '_'");
	# avoid exit status 1 if grep finds no matches
	$self->run_command("grep ':r_f:' $rawoutfile >$outdir/tmp_seqs_to_revcomp || true", "Get list of sequences to reverse complement");
	my $seqfilter_bin = $self->{seqfilter_bin};
	my $msg = "Fix orientation of sequences cropped with dispr";
	my $cmd = "$seqfilter_bin --rev-comp $outdir/tmp_seqs_to_revcomp $rawoutfile --out $outdir/sequences.dispr.fa";
	$self->run_command($cmd, $msg);
	unlink("$outdir/tmp_seqs_to_revcomp");
}

sub add_taxonomy_to_fasta{
	my $self = shift;
	my $outdir = $self->{outdir};
	$L->info("Adding taxonomy to fasta");
	my %acc2taxid = $self->get_accession_to_taxid_map();
	open IN, "<$outdir/sequences.fa" or $L->logdie("$!");
	open OUT, ">$outdir/sequences.tax.fa" or $L->logdie("$!");
	while(<IN>){
		if(/^>([^.\s]+)[.\s]/){
			$lineage = $self->get_lineage_string_for_taxid($acc2taxid{$1});
			print OUT ">$1;tax=$lineage;\n";
		}
		else{
			print OUT;
		}
	}
	close IN or $L->logdie("$!");
	close OUT or $L->logdie("$!");
	$L->info("Finished: Adding taxonomy to fasta");
}

sub get_taxa_filter_string_from_taxfile{
	my $self = shift;
	$taxa_list = $self->{taxa_list};
	return "" unless($taxa_list);
	my $taxa_filter_string = "";
	my @taxa = ();
	open IN, "<$taxa_list" or $L->logdie("$!");
	while(<IN>){
		chomp;
		my $taxon = $_."[ORGN]";
		push(@taxa, $taxon);
	}
	close IN or $L->logdie("$!");
	return "" unless(@taxa);
	return " AND (".join(" OR ", @taxa).")";
}

sub get_lineage_string_for_taxid{
	my $self = shift;
	my $taxid = shift;
	my @lineage = @{NCBI::Taxonomy::getlineagebytaxid($taxid)};
    my %tax_elements;
    foreach my $tax_element (@lineage){
		$tax_elements{$tax_element->{rank}} = $tax_element->{sciname};
    }
	my @lineage_elements = ();
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'kingdom'));
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'domain'));
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'phylum'));
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'class'));
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'order'));
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'family'));
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'genus'));
	push(@lineage_elements, $self->get_tax_string_for_level(\%tax_elements, 'species'));
	my $tax_string = join(",",grep {$_} @lineage_elements);
	# replace whitespace with _, this is not required for sintax but for most other downstream tools
	$tax_string =~ s/ /_/g;
	return $tax_string;
}

sub get_tax_string_for_level{
	my $self = shift;
    my $tax_elements = shift;
	my $level = shift;
    my $prefix = substr($level, 0, 1);
	my $taxstring = "";
    if(defined $tax_elements->{$level}){
		$taxstring = $prefix.":".$tax_elements->{$level};
    }
    return $taxstring;
}

sub get_accession_to_taxid_map{
	my $self = shift;
	my $outdir = $self->{outdir};
	my %acc2taxid = {};
	open IN, "<$outdir/list.filtered.txt" or $L->logdie("$!");
	while(<IN>){
		chomp;
		my ($acc, $taxid) = split;
		$acc2taxid{$acc} = $taxid;
	}
	close IN or $L->logdie("$!");
	return %acc2taxid;
}

sub combine_filtered_and_raw_sequences{
	my $self = shift;
	my $outdir = $self->{outdir};
	my $primer_file = $self->{primer_file};
	return unless($primer_file);
	my $seqfilter_bin = $self->{seqfilter_bin};
	my $dispr_file = "$outdir/sequences.dispr.fa";
	$self->run_command("grep '^>' $dispr_file | cut -f1 -d';' >$outdir/tmp_seqs_clean || true", "Get list of filtered sequences (to exclude the raw ones)");
	$self->run_command("sed 's/;/ ;/' $outdir/sequences.tax.fa >$outdir/tmp_seqs_fix_header", "Create file with fixed header for filtering");
	$L->info("Combine filtered and raw sequences (use filtered if available, else use raw)");
	my $msg = "Extract raw sequences that have no filtered version";
	my $cmd = "$seqfilter_bin --ids-exclude --ids $outdir/tmp_seqs_clean $outdir/tmp_seqs_fix_header --out - | sed 's/ ;tax/;tax/' >$outdir/sequences.combined.fa";
	$self->run_command($cmd, $msg);
	unlink("$outdir/tmp_seqs_clean");
	unlink("$outdir/tmp_seqs_fix_header");
	my $msg = "Add filtered sequences where available";
	my $cmd = "cat $dispr_file >>$outdir/sequences.combined.fa";
	$self->run_command($cmd, $msg);
}

sub create_krona_summary{
	my $self = shift;
	my $outdir = $self->{outdir};
	my $krona_bin = $self->{krona_bin};
	my $msg = "Create krona chart for taxonomy distribution in database";
	my $cmd = "$krona_bin -t 2 -o $outdir/taxonomy.krona.html $outdir/list.filtered.txt";
	$self->run_command($cmd, $msg);
}

sub add_citation_file{
	my $self = shift;
	my $outdir = $self->{outdir};
	$self->run_command("cp $FindBin::RealBin/../CITATION $outdir/", "Add CITATION file to output directory");
}

sub run_command{
	my $self = shift;
	my $cmd = shift;
	my $msg = shift;
	my $ignore_error = shift;
	$L->info("Starting: $msg");
	$L->info($cmd);
	my $result = qx($cmd);
	$L->debug($result);
	$L->logdie("ERROR: $msg failed") if $? >> 8 and !$ignore_error;
	$L->info("Finished: $msg");
	return $result;
}


1;