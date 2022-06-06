" Returns the name of CMake generator
function! utils#gen#xcode#getGeneratorName() abort
    return 'Xcode'
endfunction

" Returns the default target for current CMake generator
function! utils#gen#xcode#getDefaultTarget() abort
    return 'ALL_BUILD'
endfunction

" Returns the clean target for CMake generator
function! utils#gen#xcode#getCleanTarget() abort
    return 'clean'
endfunction

" Returns the list of targets for CMake generator
function! utils#gen#xcode#getTargets(build_dir) abort
    return json_decode(system(printf('%s --build %s -- -list -json 2>/dev/null', g:cmake_executable, a:build_dir)))['project']['targets']
endfunction

" Returns the cmake build command for CMake generator
function! utils#gen#xcode#getBuildCommand(build_dir, target, make_arguments) abort
    let l:cmd = printf('%s --build %s --target %s -- ', g:cmake_executable, utils#fs#fnameescape(a:build_dir), a:target )
    let l:cmd .= a:make_arguments
    return l:cmd
endfunction
