#!/usr/local/bin/perl

package Authen::NTLM;
use strict;
Authen::NTLM::DES->import();
Authen::NTLM::MD4->import();
use MIME::Base64;
use Digest::HMAC_MD5;

use vars qw($VERSION @ISA @EXPORT);
require Exporter;

=head1 NAME

Authen::NTLM - An NTLM authentication module

=head1 SYNOPSIS

    use Mail::IMAPClient;
    use Authen::NTLM;
    my $imap = Mail::IMAPClient->new(Server=>'imaphost');
    ntlm_user($username);
    ntlm_password($password);
    $imap->authenticate("NTLM", Authen::NTLM::ntlm);
    :
    $imap->logout;
    ntlm_reset;
    :

or

    ntlmv2(1);
    ntlm_user($username);
    ntlm_host($host);
    ntlm_password($password);
    :

or

    my $ntlm = Authen::NTLM-> new(
        host     => $host,
        user     => $username,
        domain   => $domain,
        password => $password,
        version  => 1,
    );
    $ntlm-> challenge;
    :
    $ntlm-> challenge($challenge);



=head1 DESCRIPTION

    This module provides methods to use NTLM authentication.  It can
    be used as an authenticate method with the Mail::IMAPClient module
    to perform the challenge/response mechanism for NTLM connections
    or it can be used on its own for NTLM authentication with other
    protocols (eg. HTTP).

    The implementation is a direct port of the code from F<fetchmail>
    which, itself, has based its NTLM implementation on F<samba>.  As
    such, this code is not especially efficient, however it will still
    take a fraction of a second to negotiate a login on a PII which is
    likely to be good enough for most situations.

=head2 FUNCTIONS

=over 4

=item ntlm_domain()

    Set the domain to use in the NTLM authentication messages.
    Returns the new domain.  Without an argument, this function
    returns the current domain entry.

=item ntlm_user()

    Set the username to use in the NTLM authentication messages.
    Returns the new username.  Without an argument, this function
    returns the current username entry.

=item ntlm_password()

    Set the password to use in the NTLM authentication messages.
    Returns the new password.  Without an argument, this function
    returns the current password entry.

=item ntlm_reset()

    Resets the NTLM challenge/response state machine so that the next
    call to C<ntlm()> will produce an initial connect message.

=item ntlm()

    Generate a reply to a challenge.  The NTLM protocol involves an
    initial empty challenge from the server requiring a message
    response containing the username and domain (which may be empty).
    The first call to C<ntlm()> generates this first message ignoring
    any arguments.

    The second time it is called, it is assumed that the argument is
    the challenge string sent from the server.  This will contain 8
    bytes of data which are used in the DES functions to generate the
    response authentication strings.  The result of the call is the
    final authentication string.

    If C<ntlm_reset()> is called, then the next call to C<ntlm()> will
    start the process again allowing multiple authentications within
    an application.

=item ntlmv2()

    Use NTLM v2 authentication.

=back

=head2 OBJECT API

=over

=item new %options

Creates an object that accepts the following options: C<user>, C<host>,
C<domain>, C<password>, C<version>.

=item challenge [$challenge]

If C<$challenge> is not supplied, first-stage challenge string is generated.
Otherwise, the third-stage challenge is generated, where C<$challenge> is
assumed to be extracted from the second stage of NTLM exchange. The result of
the call is the final authentication string.

=back

=head1 AUTHOR

    David (Buzz) Bussenschutt <davidbuzz@gmail.com> - current maintainer
    Dmitry Karasik <dmitry@karasik.eu.org> - nice ntlmv2 patch, OO extensions.
    Andrew Hobson <ahobson@infloop.com> - initial ntlmv2 code
    Mark Bush <Mark.Bush@bushnet.demon.co.uk> - perl port
    Eric S. Raymond - author of fetchmail
    Andrew Tridgell and Jeremy Allison for SMB/Netbios code

=head1 SEE ALSO

L<perl>, L<Mail::IMAPClient>, L<LWP::Authen::Ntlm>

=head1 HISTORY

    1.09 - fix CPAN ticket # 70703
    1.08 - fix CPAN ticket # 39925
    1.07 - not publicly released
    1.06 - relicense as GPL+ or Artistic
    1.05 - add OO interface by Dmitry Karasik
    1.04 - implementation of NTLMv2 by Andrew Hobson/Dmitry Karasik
    1.03 - fixes long-standing 1 line bug L<http://rt.cpan.org/Public/Bug/Display.html?id=9521> - released by David Bussenschutt 9th Aug 2007
    1.02 - released by Mark Bush 29th Oct 2001

=cut

$VERSION = "1.09";
@ISA = qw(Exporter);
@EXPORT = qw(ntlm ntlm_domain ntlm_user ntlm_password ntlm_reset ntlm_host ntlmv2);

my $domain = "";
my $user = "";
my $password = "";

my $str_hdr = "vvV";
my $hdr_len = 8;
my $ident = "NTLMSSP";

my $msg1_f = 0x0000b207;
my $msg1 = "Z8VV";
my $msg1_hlen = 16 + ($hdr_len*2);

my $msg2 = "Z8Va${hdr_len}Va8a8a${hdr_len}";
my $msg2_hlen = 12 + $hdr_len + 20 + $hdr_len;

my $msg3 = "Z8V";
my $msg3_tl = "V";
my $msg3_hlen = 12 + ($hdr_len*6) + 4;

my $state = 0;

my $host = "";
my $ntlm_v2 = 0;
my $ntlm_v2_msg3_flags = 0x88205;


# Domain Name supplied on negotiate
use constant NTLMSSP_NEGOTIATE_OEM_DOMAIN_SUPPLIED      => 0x00001000;
# Workstation Name supplied on negotiate
use constant NTLMSSP_NEGOTIATE_OEM_WORKSTATION_SUPPLIED => 0x00002000;
# Try to use NTLMv2
use constant NTLMSSP_NEGOTIATE_NTLM2                    => 0x00080000;


# Object API

sub new
{
    my ( $class, %opt) = @_;
    for (qw(domain user password host)) {
        $opt{$_} = "" unless defined $opt{$_};
    }
    $opt{version} ||= 1;
    return bless { %opt }, $class;
}

sub challenge
{
    my ( $self, $challenge) = @_;
    $state = defined $challenge;
    ($user,$domain,$password,$host) = @{$self}{qw(user domain password host)};
    $ntlm_v2 = ($self-> {version} eq '2') ? 1 : 0;
    return ntlm($challenge);
}

eval "sub $_ { \$#_ ? \$_[0]->{$_} = \$_[1] : \$_[0]->{$_} }"
    for qw(user domain password host version);

# Function API

sub ntlm_domain
{
    if (@_)
    {
        $domain = shift;
    }
    return $domain;
}

sub ntlm_user
{
    if (@_)
    {
        $user = shift;
    }
    return $user;
}

sub ntlm_password
{
    if (@_)
    {
        $password = shift;
    }
    return $password;
}

sub ntlm_reset
{
    $state = 0;
}

sub ntlmv2
{
    if (@_) {
        $ntlm_v2 = shift;
    }
    return $ntlm_v2;
}

sub ntlm_host {
    if (@_) {
        $host = shift;
    }
    return $host;
}

sub ntlm
{
    my ($challenge) = @_;

    my ($flags, $user_hdr, $domain_hdr,
        $u_off, $d_off, $c_info, $lmResp, $ntResp, $lm_hdr,
        $nt_hdr, $wks_hdr, $session_hdr, $lm_off, $nt_off,
        $wks_off, $s_off, $u_user, $msg1_host, $host_hdr, $u_host);
    my $response;
    if ($state)
    {

        $challenge =~ s/^\s*//;
        $challenge = decode_base64($challenge);
        $c_info = &decode_challenge($challenge);
        $u_user = &unicode($user);
        if (!$ntlm_v2) {
            $domain = substr($challenge, $c_info->{domain}{offset}, $c_info->{domain}{len});
            $lmResp = &lmEncrypt($c_info->{data});
            $ntResp = &ntEncrypt($c_info->{data});
            $flags = pack($msg3_tl, $c_info->{flags});
        }
        elsif ($ntlm_v2 eq '1') {
            $lmResp = &lmv2Encrypt($c_info->{data});
            $ntResp = &ntv2Encrypt($c_info->{data}, $c_info->{target_data});
            $flags = pack($msg3_tl, $ntlm_v2_msg3_flags);
        }
        else {
            $domain = &unicode($domain);#substr($challenge, $c_info->{domain}{offset}, $c_info->{domain}{len});
            $lmResp = &lmEncrypt($c_info->{data});
            $ntResp = &ntEncrypt($c_info->{data});
            $flags = pack($msg3_tl, $c_info->{flags});
        }
        $u_host = &unicode(($host ? $host : $user));
        $response = pack($msg3, $ident, 3);

        $lm_off = $msg3_hlen;
        $nt_off = $lm_off + length($lmResp);
        $d_off = $nt_off + length($ntResp);
        $u_off = $d_off + length($domain);
        $wks_off = $u_off + length($u_user);
        $s_off = $wks_off + length($u_host);
        $lm_hdr = &hdr($lmResp, $msg3_hlen, $lm_off);
        $nt_hdr = &hdr($ntResp, $msg3_hlen, $nt_off);
        $domain_hdr = &hdr($domain, $msg3_hlen, $d_off);
        $user_hdr = &hdr($u_user, $msg3_hlen, $u_off);
        $wks_hdr = &hdr($u_host, $msg3_hlen, $wks_off);
        $session_hdr = &hdr("", $msg3_hlen, $s_off);
        $response .= $lm_hdr . $nt_hdr . $domain_hdr . $user_hdr .
            $wks_hdr . $session_hdr . $flags .
            $lmResp . $ntResp . $domain . $u_user . $u_host;
    }
    else # first response;
    {
        my $f = $msg1_f;
        if (!length $domain) {
            $f &= ~NTLMSSP_NEGOTIATE_OEM_DOMAIN_SUPPLIED;
        }
        $msg1_host = $user;
        if ($ntlm_v2 and $ntlm_v2 eq '1') {
            $f &= ~NTLMSSP_NEGOTIATE_OEM_WORKSTATION_SUPPLIED;
            $f |= NTLMSSP_NEGOTIATE_NTLM2;
            $msg1_host = "";
        }

        $response = pack($msg1, $ident, 1, $f);
        $u_off = $msg1_hlen;
        $d_off = $u_off + length($msg1_host);
        $host_hdr = &hdr($msg1_host, $msg1_hlen, $u_off);
        $domain_hdr = &hdr($domain, $msg1_hlen, $d_off);
        $response .= $host_hdr . $domain_hdr . $msg1_host . $domain;
        $state = 1;
    }
    return encode_base64($response, "");
}

sub hdr
{
    my ($string, $h_len, $offset) = @_;

    my ($res, $len);
    $len = length($string);
    if ($string)
    {
        $res = pack($str_hdr, $len, $len, $offset);
    }
    else
    {
        $res = pack($str_hdr, 0, 0, $offset - $h_len);
    }
    return $res;
}

sub decode_challenge
{
    my ($challenge) = @_;

    my $res;
    my (@res, @hdr);
    my $original = $challenge;

    $res->{buffer} = $msg2_hlen < length $challenge
        ? substr($challenge, $msg2_hlen) : '';
    $challenge = substr($challenge, 0, $msg2_hlen);
    @res = unpack($msg2, $challenge);
    $res->{ident} = $res[0];
    $res->{type} = $res[1];
    @hdr = unpack($str_hdr, $res[2]);
    $res->{domain}{len} = $hdr[0];
    $res->{domain}{maxlen} = $hdr[1];
    $res->{domain}{offset} = $hdr[2];
    $res->{flags} = $res[3];
    $res->{data} = $res[4];
    $res->{reserved} = $res[5];
    $res->{empty_hdr} = $res[6];
    @hdr = unpack($str_hdr, $res[6]);
    $res->{target}{len} = $hdr[0];
    $res->{target}{maxlen} = $hdr[1];
    $res->{target}{offset} = $hdr[2];
    $res->{target_data} = substr($original, $hdr[2], $hdr[1]);

    return $res;
}

sub unicode
{
    my ($string) = @_;
    my ($reply, $c, $z) = ('');

    $z = sprintf "%c", 0;
    foreach $c (split //, $string)
    {
        $reply .= $c . $z;
    }
    return $reply;
}

sub NTunicode
{
    my ($string) = @_;
    my ($reply, $c);

    foreach $c (map {ord($_)} split(//, $string))
    {
        $reply .= pack("v", $c);
    }
    return $reply;
}

sub lmEncrypt
{
    my ($data) = @_;

    my $p14 = substr($password, 0, 14);
    $p14 =~ tr/a-z/A-Z/;
    $p14 .= "\0"x(14-length($p14));
    my $p21 = E_P16($p14);
    $p21 .= "\0"x(21-length($p21));
    my $p24 = E_P24($p21, $data);
    return $p24;
}

sub ntEncrypt
{
    my ($data) = @_;

    my $p21 = &E_md4hash;
    $p21 .= "\0"x(21-length($p21));
    my $p24 = E_P24($p21, $data);
    return $p24;
}

sub E_md4hash
{
    my $wpwd = &NTunicode($password);
    my $p16 = mdfour($wpwd);
    return $p16;
}

sub lmv2Encrypt {
    my ($data) = @_;

    my $u_pass = &unicode($password);
    my $ntlm_hash = mdfour($u_pass);

    my $u_user = &unicode("\U$user\E");
    my $u_domain = &unicode("$domain");
    my $concat = $u_user . $u_domain;

    my $hmac = Digest::HMAC_MD5->new($ntlm_hash);
    $hmac->add($concat);
    my $ntlm_v2_hash = $hmac->digest;

    # Firefox seems to use this as its random challenge
    my $random_challenge = "\0" x 8;

    my $concat2 = $data . $random_challenge;

    $hmac = Digest::HMAC_MD5->new($ntlm_v2_hash);
    $hmac->add(substr($data, 0, 8) . $random_challenge);
    my $r = $hmac->digest . $random_challenge;

    return $r;
}

sub ntv2Encrypt {
    my ($data, $target) = @_;

    my $u_pass = &unicode($password);
    my $ntlm_hash = mdfour($u_pass);

    my $u_user = &unicode("\U$user\E");
    my $u_domain = &unicode("$domain");
    my $concat = $u_user . $u_domain;

    my $hmac = Digest::HMAC_MD5->new($ntlm_hash);
    $hmac->add($concat);
    my $ntlm_v2_hash = $hmac->digest;

    my $zero_long = "\000" x 4;
    my $sig = pack("H8", "01010000");
    my $time = pack("VV", (time + 11644473600) + 10000000);
    my $rand = "\0" x 8;
    my $blob = $sig . $zero_long . $time . $rand . $zero_long .
        $target . $zero_long;

    $concat = $data . $blob;

    $hmac = Digest::HMAC_MD5->new($ntlm_v2_hash);
    $hmac->add($concat);

    my $d = $hmac->digest;

    my $r = $d . $blob;

    return $r;
}

1;

package Authen::NTLM::DES;

use vars qw($VERSION @ISA @EXPORT);
require Exporter;

$VERSION = "1.02";
@ISA = qw(Exporter);
@EXPORT = qw(E_P16 E_P24);

my ($loop, $loop2);
$loop = 0;
$loop2 = 0;

my $perm1 = [57, 49, 41, 33, 25, 17, 9,
    1, 58, 50, 42, 34, 26, 18,
    10, 2, 59, 51, 43, 35, 27,
    19, 11, 3, 60, 52, 44, 36,
    63, 55, 47, 39, 31, 23, 15,
    7, 62, 54, 46, 38, 30, 22,
    14, 6, 61, 53, 45, 37, 29,
    21, 13, 5, 28, 20, 12, 4];
my $perm2 = [14, 17, 11, 24, 1, 5,
    3, 28, 15, 6, 21, 10,
    23, 19, 12, 4, 26, 8,
    16, 7, 27, 20, 13, 2,
    41, 52, 31, 37, 47, 55,
    30, 40, 51, 45, 33, 48,
    44, 49, 39, 56, 34, 53,
    46, 42, 50, 36, 29, 32];
my $perm3 = [58, 50, 42, 34, 26, 18, 10, 2,
    60, 52, 44, 36, 28, 20, 12, 4,
    62, 54, 46, 38, 30, 22, 14, 6,
    64, 56, 48, 40, 32, 24, 16, 8,
    57, 49, 41, 33, 25, 17, 9, 1,
    59, 51, 43, 35, 27, 19, 11, 3,
    61, 53, 45, 37, 29, 21, 13, 5,
    63, 55, 47, 39, 31, 23, 15, 7];
my $perm4 = [32, 1, 2, 3, 4, 5,
    4, 5, 6, 7, 8, 9,
    8, 9, 10, 11, 12, 13,
    12, 13, 14, 15, 16, 17,
    16, 17, 18, 19, 20, 21,
    20, 21, 22, 23, 24, 25,
    24, 25, 26, 27, 28, 29,
    28, 29, 30, 31, 32, 1];
my $perm5 = [16, 7, 20, 21, 29, 12, 28, 17,
    1, 15, 23, 26, 5, 18, 31, 10,
    2, 8, 24, 14, 32, 27, 3, 9,
    19, 13, 30, 6, 22, 11, 4, 25];
my $perm6 = [40, 8, 48, 16, 56, 24, 64, 32,
    39, 7, 47, 15, 55, 23, 63, 31,
    38, 6, 46, 14, 54, 22, 62, 30,
    37, 5, 45, 13, 53, 21, 61, 29,
    36, 4, 44, 12, 52, 20, 60, 28,
    35, 3, 43, 11, 51, 19, 59, 27,
    34, 2, 42, 10, 50, 18, 58, 26,
    33, 1, 41,  9, 49, 17, 57, 25];
my $sc = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];
my $sbox = [
    [
        [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
        [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
        [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
        [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13]
    ],
    [
        [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
        [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
        [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
        [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9]
    ],
    [
        [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
        [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
        [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
        [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12]
    ],
    [
        [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
        [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
        [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
        [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14]
    ],
    [
        [2,12,4,1,7,10,11,6,8,5,3,15,13,0,14,9],
        [14,11,2,12,4,7,13,1,5,0,15,10,3,9,8,6],
        [4,2,1,11,10,13,7,8,15,9,12,5,6,3,0,14],
        [11,8,12,7,1,14,2,13,6,15,0,9,10,4,5,3]
    ],
    [
        [12,1,10,15,9,2,6,8,0,13,3,4,14,7,5,11],
        [10,15,4,2,7,12,9,5,6,1,13,14,0,11,3,8],
        [9,14,15,5,2,8,12,3,7,0,4,10,1,13,11,6],
        [4,3,2,12,9,5,15,10,11,14,1,7,6,0,8,13]
    ],
    [
        [4,11,2,14,15,0,8,13,3,12,9,7,5,10,6,1],
        [13,0,11,7,4,9,1,10,14,3,5,12,2,15,8,6],
        [1,4,11,13,12,3,7,14,10,15,6,8,0,5,9,2],
        [6,11,13,8,1,4,10,7,9,5,0,15,14,2,3,12]
    ],
    [
        [13,2,8,4,6,15,11,1,10,9,3,14,5,0,12,7],
        [1,15,13,8,10,3,7,4,12,5,6,11,0,14,9,2],
        [7,11,4,1,9,12,14,2,0,6,10,13,15,3,5,8],
        [2,1,14,7,4,10,8,13,15,12,9,0,3,5,6,11]
    ]
];

sub E_P16
{
    my ($p14) = @_;
    my $sp8 = [0x4b, 0x47, 0x53, 0x21, 0x40, 0x23, 0x24, 0x25];

    my $p7 = substr($p14, 0, 7);
    my $p16 = smbhash($sp8, $p7);
    $p7 = substr($p14, 7, 7);
    $p16 .= smbhash($sp8, $p7);
    return $p16;
}

sub E_P24
{
    my ($p21, $c8_str) = @_;
    my @c8 = map {ord($_)} split(//, $c8_str);
    my $p24 = smbhash(\@c8, substr($p21, 0, 7));
    $p24 .= smbhash(\@c8, substr($p21, 7, 7));
    $p24 .= smbhash(\@c8, substr($p21, 14, 7));
}

sub permute
{
    my ($out, $in, $p, $n) = @_;
    my $i;

    foreach $i (0..($n-1))
    {
        $out->[$i] = $in->[$p->[$i]-1];
    }
}

sub lshift
{
    my ($d, $count, $n) = @_;
    my (@out, $i);

    foreach $i (0..($n-1))
    {
        $out[$i] = $d->[($i+$count)%$n];
    }
    foreach $i (0..($n-1))
    {
        $d->[$i] = $out[$i];
    }
}

sub xor
{
    my ($out, $in1, $in2, $n) = @_;
    my $i;

    foreach $i (0..($n-1))
    {
        $out->[$i] = $in1->[$i]^$in2->[$i];
    }
}

sub dohash
{
    my ($out, $in, $key) = @_;
    my ($i, $j, $k, @pk1, @c, @d, @cd,
        @ki, @pd1, @l, @r, @rl);

    &permute(\@pk1, $key, $perm1, 56);

    foreach $i (0..27)
    {
        $c[$i] = $pk1[$i];
        $d[$i] = $pk1[$i+28];
    }
    foreach $i (0..15)
    {
        my @array;
        &lshift(\@c, $sc->[$i], 28);
        &lshift(\@d, $sc->[$i], 28);
        @cd = (@c, @d);
        &permute(\@array, \@cd, $perm2, 48);
        $ki[$i] = \@array;
    }
    &permute(\@pd1, $in, $perm3, 64);

    foreach $j (0..31)
    {
        $l[$j] = $pd1[$j];
        $r[$j] = $pd1[$j+32];
    }

    foreach $i (0..15)
    {
        local (@er, @erk, @b, @cb, @pcb, @r2);
        permute(\@er, \@r, $perm4, 48);
        &xor(\@erk, \@er, $ki[$i], 48);
        foreach $j (0..7)
        {
            foreach $k (0..5)
            {
                $b[$j][$k] = $erk[$j*6+$k];
            }
        }
        foreach $j (0..7)
        {
            local ($m, $n);
            $m = ($b[$j][0]<<1) | $b[$j][5];
            $n = ($b[$j][1]<<3) | ($b[$j][2]<<2) | ($b[$j][3]<<1) | $b[$j][4];
            foreach $k (0..3)
            {
                $b[$j][$k] = ($sbox->[$j][$m][$n] & (1<<(3-$k)))? 1: 0;
            }
        }
        foreach $j (0..7)
        {
            foreach $k (0..3)
            {
                $cb[$j*4+$k] = $b[$j][$k];
            }
        }
        &permute(\@pcb, \@cb, $perm5, 32);
        &xor(\@r2, \@l, \@pcb, 32);
        foreach $j (0..31)
        {
            $l[$j] = $r[$j];
            $r[$j] = $r2[$j];
        }
    }
    @rl = (@r, @l);
    &permute($out, \@rl, $perm6, 64);
}

sub str_to_key
{
    my ($str) = @_;
    my $i;
    my @key;
    my $out;
    my @str = map {ord($_)} split(//, $str);
    $key[0] = $str[0]>>1;
    $key[1] = (($str[0]&0x01)<<6) | ($str[1]>>2);
    $key[2] = (($str[1]&0x03)<<5) | ($str[2]>>3);
    $key[3] = (($str[2]&0x07)<<4) | ($str[3]>>4);
    $key[4] = (($str[3]&0x0f)<<3) | ($str[4]>>5);
    $key[5] = (($str[4]&0x1f)<<2) | ($str[5]>>6);
    $key[6] = (($str[5]&0x3f)<<1) | ($str[6]>>7);
    $key[7] = $str[6]&0x7f;
    foreach $i (0..7)
    {
        $key[$i] = 0xff&($key[$i]<<1);
    }
    return \@key;
}

sub smbhash
{
    my ($in, $key) = @_;

    my $key2 = &str_to_key($key);
    my ($i, $div, $mod, @in, @outb, @inb, @keyb, @out);
    foreach $i (0..63)
    {
        $div = int($i/8); $mod = $i%8;
        $inb[$i] = ($in->[$div] & (1<<(7-($mod))))? 1: 0;
        $keyb[$i] = ($key2->[$div] & (1<<(7-($mod))))? 1: 0;
        $outb[$i] = 0;
    }
    &dohash(\@outb, \@inb, \@keyb);
    foreach $i (0..7)
    {
        $out[$i] = 0;
    }
    foreach $i (0..63)
    {
        $out[int($i/8)] |= (1<<(7-($i%8))) if ($outb[$i]);
    }
    my $out = pack("C8", @out);
    return $out;
}

1;

package Authen::NTLM::MD4;

use vars qw($VERSION @ISA @EXPORT);
require Exporter;

$VERSION = "1.02";
@ISA = qw(Exporter);
@EXPORT = qw(mdfour);

my ($A, $B, $C, $D);
my (@X, $M);

sub mdfour
{
    my ($in) = @_;

    my ($i, $pos);
    my $len = length($in);
    my $b = $len * 8;
    $in .= "\0"x128;
    $A = 0x67452301;
    $B = 0xefcdab89;
    $C = 0x98badcfe;
    $D = 0x10325476;
    $pos = 0;
    while ($len > 64)
    {
        &copy64(substr($in, $pos, 64));
        &mdfour64;
        $pos += 64;
        $len -= 64;
    }
    my $buf = substr($in, $pos, $len);
    $buf .= sprintf "%c", 0x80;
    if ($len <= 55)
    {
        $buf .= "\0"x(55-$len);
        $buf .= pack("V", $b);
        $buf .= "\0"x4;
        &copy64($buf);
        &mdfour64;
    }
    else
    {
        $buf .= "\0"x(120-$len);
        $buf .= pack("V", $b);
        $buf .= "\0"x4;
        &copy64(substr($buf, 0, 64));
        &mdfour64;
        &copy64(substr($buf, 64, 64));
        &mdfour64;
    }
    my $out = pack("VVVV", $A, $B, $C, $D);
    return $out;
}

sub F
{
    my ($X, $Y, $Z) = @_;
    my $res = ($X&$Y) | ((~$X)&$Z);
    return $res;
}

sub G
{
    my ($X, $Y, $Z) = @_;

    return ($X&$Y) | ($X&$Z) | ($Y&$Z);
}

sub H
{
    my ($X, $Y, $Z) = @_;

    return $X^$Y^$Z;
}

sub lshift
{
    my ($x, $s) = @_;

    $x &= 0xffffffff;
    return (($x<<$s)&0xffffffff) | ($x>>(32-$s));
}

sub ROUND1
{
    my ($a, $b, $c, $d, $k, $s) = @_;
    my $e = &add($a, &F($b, $c, $d), $X[$k]);
    return &lshift($e, $s);
}

sub ROUND2
{
    my ($a, $b, $c, $d, $k, $s) = @_;

    my $e = &add($a, &G($b, $c, $d), $X[$k], 0x5a827999);
    return &lshift($e, $s);
}

sub ROUND3
{
    my ($a, $b, $c, $d, $k, $s) = @_;

    my $e = &add($a, &H($b, $c, $d), $X[$k], 0x6ed9eba1);
    return &lshift($e, $s);
}

sub mdfour64
{
    my ($i, $AA, $BB, $CC, $DD);
    @X = unpack("N16", $M);
    $AA = $A;
    $BB = $B;
    $CC = $C;
    $DD = $D;

    $A = &ROUND1($A,$B,$C,$D, 0, 3); $D = &ROUND1($D,$A,$B,$C, 1, 7);
    $C = &ROUND1($C,$D,$A,$B, 2,11); $B = &ROUND1($B,$C,$D,$A, 3,19);
    $A = &ROUND1($A,$B,$C,$D, 4, 3); $D = &ROUND1($D,$A,$B,$C, 5, 7);
    $C = &ROUND1($C,$D,$A,$B, 6,11); $B = &ROUND1($B,$C,$D,$A, 7,19);
    $A = &ROUND1($A,$B,$C,$D, 8, 3); $D = &ROUND1($D,$A,$B,$C, 9, 7);
    $C = &ROUND1($C,$D,$A,$B,10,11); $B = &ROUND1($B,$C,$D,$A,11,19);
    $A = &ROUND1($A,$B,$C,$D,12, 3); $D = &ROUND1($D,$A,$B,$C,13, 7);
    $C = &ROUND1($C,$D,$A,$B,14,11); $B = &ROUND1($B,$C,$D,$A,15,19);

    $A = &ROUND2($A,$B,$C,$D, 0, 3); $D = &ROUND2($D,$A,$B,$C, 4, 5);
    $C = &ROUND2($C,$D,$A,$B, 8, 9); $B = &ROUND2($B,$C,$D,$A,12,13);
    $A = &ROUND2($A,$B,$C,$D, 1, 3); $D = &ROUND2($D,$A,$B,$C, 5, 5);
    $C = &ROUND2($C,$D,$A,$B, 9, 9); $B = &ROUND2($B,$C,$D,$A,13,13);
    $A = &ROUND2($A,$B,$C,$D, 2, 3); $D = &ROUND2($D,$A,$B,$C, 6, 5);
    $C = &ROUND2($C,$D,$A,$B,10, 9); $B = &ROUND2($B,$C,$D,$A,14,13);
    $A = &ROUND2($A,$B,$C,$D, 3, 3); $D = &ROUND2($D,$A,$B,$C, 7, 5);
    $C = &ROUND2($C,$D,$A,$B,11, 9); $B = &ROUND2($B,$C,$D,$A,15,13);

    $A = &ROUND3($A,$B,$C,$D, 0, 3); $D = &ROUND3($D,$A,$B,$C, 8, 9);
    $C = &ROUND3($C,$D,$A,$B, 4,11); $B = &ROUND3($B,$C,$D,$A,12,15);
    $A = &ROUND3($A,$B,$C,$D, 2, 3); $D = &ROUND3($D,$A,$B,$C,10, 9);
    $C = &ROUND3($C,$D,$A,$B, 6,11); $B = &ROUND3($B,$C,$D,$A,14,15);
    $A = &ROUND3($A,$B,$C,$D, 1, 3); $D = &ROUND3($D,$A,$B,$C, 9, 9);
    $C = &ROUND3($C,$D,$A,$B, 5,11); $B = &ROUND3($B,$C,$D,$A,13,15);
    $A = &ROUND3($A,$B,$C,$D, 3, 3); $D = &ROUND3($D,$A,$B,$C,11, 9);
    $C = &ROUND3($C,$D,$A,$B, 7,11); $B = &ROUND3($B,$C,$D,$A,15,15);

    $A = &add($A, $AA); $B = &add($B, $BB);
    $C = &add($C, $CC); $D = &add($D, $DD);
    $A &= 0xffffffff; $B &= 0xffffffff;
    $C &= 0xffffffff; $D &= 0xffffffff;
    map {$_ = 0} @X;
}

sub copy64
{
    my ($in) = @_;

    $M = pack("V16", unpack("N16", $in));
}

# see note at top of this file about this function
sub add
{
    my (@nums) = @_;
    my ($r_low, $r_high, $n_low, $l_high);
    my $num;
    $r_low = $r_high = 0;
    foreach $num (@nums)
    {
        $n_low = $num & 0xffff;
        $n_high = ($num&0xffff0000)>>16;
        $r_low += $n_low;
        ($r_low&0xf0000) && $r_high++;
        $r_low &= 0xffff;
        $r_high += $n_high;
        $r_high &= 0xffff;
    }
    return ($r_high<<16)|$r_low;
}

1;