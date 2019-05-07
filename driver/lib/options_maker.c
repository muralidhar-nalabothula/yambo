/*
         Copyright (C) 2000-2019 the YAMBO team
               http://www.yambo-code.org
 
  Authors (see AUTHORS file for details): AM
  
  This file is distributed under the terms of the GNU 
  General Public License. You can redistribute it and/or 
  modify it under the terms of the GNU General Public 
  License as published by the Free Software Foundation; 
  either version 2, or (at your option) any later version.
 
  This program is distributed in the hope that it will 
  be useful, but WITHOUT ANY WARRANTY; without even the 
  implied warranty of MERCHANTABILITY or FITNESS FOR A 
  PARTICULAR PURPOSE.  See the GNU General Public License 
  for more details.
 
  You should have received a copy of the GNU General Public 
  License along with this program; if not, write to the Free 
  Software Foundation, Inc., 59 Temple Place - Suite 330,Boston, 
  MA 02111-1307, USA or visit http://www.gnu.org/copyleft/gpl.txt.

*/
#include <stdio.h>
#include <kind.h>
#include <driver.h>
#include <stdlib.h>

void options_maker(struct options_struct options[])
{
 int i_opt,dummy,i;
 for(i_opt=0;i_opt<100;i_opt++) {
  options[i_opt].long_opt=NULL;
  options[i_opt].short_opt=0;
  options[i_opt].short_desc=NULL;
  for(i=0;i<=10;i++) options[i_opt].long_desc[i]=NULL;
  options[i_opt].yambo_string=NULL;
  options[i_opt].bin="all";
  options[i_opt].n_int=0;
  options[i_opt].n_float=0;
  options[i_opt].n_char=0;
  options[i_opt].serial_var=0;
  options[i_opt].optional_var=0;
  options[i_opt].no_GPL=0;
  options[i_opt].section="undef";
 }
 i_opt=-1;
 /* 
  Help(s) 
 */
 options_help(options,&i_opt);
 /* 
  Control(s)
 */
 options_control(options,&i_opt);
 /* 
  Yambo
 */
 options_yambo(options,&i_opt);
 /* 
  Projects
 */
 options_projects(options,&i_opt);
 /* 
  Interfaces
 */
 options_interfaces(options,&i_opt);
 /* 
  Assign dummy short options to variables with only long options
 */
 dummy=57;
 for(i_opt=0;i_opt<100;i_opt++){
  if (options[i_opt].short_opt > 0 ) continue;
  options[i_opt].short_opt=dummy;
  dummy--;
 }
}
