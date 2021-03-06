# ExtractCputime.pm
package MMTests::ExtractCputime;
use MMTests::Extract;
our @ISA = qw(MMTests::Extract); 

sub new() {
	my $class = shift;
	my $self = {
		_ModuleName  => "ExtractCputime",
		_DataType    => MMTests::Extract::DATA_CPUTIME,
		_ResultData  => []
	};
	bless $self, $class;
	return $self;
}

sub extractReport($$$) {
	my ($self, $reportDir, $reportName) = @_;
	my ($user, $system, $elapsed, $cpu);
	my $file = "$reportDir/noprofile/time";

	if (! -e $file) {
		$file = "$reportDir/fine-profile-timer/time";
	}

	open(INPUT, $file) || die("Failed to open $file\n");
	while (<INPUT>) {
		$_ =~ tr/[a-zA-Z]%//d;
		($user, $system, $elapsed, $cpu) = split(/\s/, $_);
		my @elements = split(/:/, $elapsed);
		my ($hours, $minutes, $seconds);
		if ($#elements == 1) {
			$hours = 0;
			($minutes, $seconds) = @elements;
		} else {
			($hours, $minutes, $seconds) = @elements;
		}
		$elapsed = $hours * 60 * 60 + $minutes * 60 + $seconds;
		
		push @{$self->{_ResultData}}, [ $user, $system, $elapsed, $cpu ];
	}
	close INPUT;
}

1;
