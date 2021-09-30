" autoload/utils/exec/job.vim - contains executable helpers
" Maintainer:   Ilya Churaev <https://github.com/ilyachur>

" Private functions {{{ "
const s:cmake4vim_buf = 'cmake4vim_execute'

let s:job_bufid = -1
let s:cmake4vim_job       = {}
let s:cmake4vim_jobs_pool = []

function! s:closeBuffer() abort
    if s:job_bufid == -1
        return
    endif

    exec 'bwipeout ' . s:job_bufid
    let s:job_bufid = -1
endfunction

function! s:createQuickFix() abort
    if s:job_bufid == -1
        return
    endif

    " just to be sure all messages were processed
    sleep 100m

    let l:old_error = &errorformat
    if !empty( s:cmake4vim_job['err_fmt'] )
        let &errorformat = s:cmake4vim_job['err_fmt']
    endif

    silent execute 'cgetbuffer ' . s:job_bufid
    silent call setqflist( [], 'a', { 'title' : s:cmake4vim_job[ 'cmd' ] } )

    if s:cmake4vim_job['err_fmt'] !=# ''
        let &errorformat = l:old_error
    endif
endfunction

function! s:vimClose(channel) abort
    let l:open_qf = get(s:cmake4vim_job, 'open_qf', 0)

    let l:ret_code = s:cmake4vim_job['job']->job_info()['exitval']
    if l:ret_code == 0
        echon "Success!\n" . s:cmake4vim_job['cmd']
    else
        echon "Failure!\n" . s:cmake4vim_job['cmd']
    endif

    " Clean the job pool if exit code is not equal to 0
    if l:ret_code != 0
        let s:cmake4vim_jobs_pool = []
    endif

    call s:createQuickFix()
    call s:closeBuffer()

    let s:cmake4vim_job = {}

    if !empty(s:cmake4vim_jobs_pool)
        let [ l:next_job; s:cmake4vim_jobs_pool ] = s:cmake4vim_jobs_pool
        silent call utils#exec#job#run(l:next_job['cmd'], l:next_job['open_qf'], l:next_job['err_fmt'])
    endif

    if l:open_qf == 0
        silent cwindow
    else
        silent copen
    endif
endfunction

function! s:nVimOut(job_id, data, event) abort
    call setbufvar(s:job_bufid, '&modifiable', 1)
    for val in filter(a:data, '!empty(v:val)')
        silent call appendbufline(s:job_bufid, '$', trim(val, "\r\n"))
        normal! G
    endfor
    call setbufvar(s:job_bufid, '&modifiable', 0)
endfunction

function! s:nVimExit(job_id, ret_code, event) abort
    let l:open_qf = s:cmake4vim_job['open_qf']

    " using only appendbufline results in an empty first line
    call setbufvar(s:job_bufid, '&modifiable', 1)
    call deletebufline( s:job_bufid, 1 )
    call setbufvar( s:job_bufid, '&modifiable', 0 )

    " Clean the job pool if exit code is not equal to 0
    if a:ret_code != 0
        let s:cmake4vim_jobs_pool = []
        echon "Failure!\n" . s:cmake4vim_job['cmd']
    else
        echon "Success!\n" . s:cmake4vim_job['cmd']
    endif

    call s:createQuickFix()
    call s:closeBuffer()

    let s:cmake4vim_job = {}

    if !empty(s:cmake4vim_jobs_pool)
        let [ l:next_job; s:cmake4vim_jobs_pool ] = s:cmake4vim_jobs_pool
        silent call utils#exec#job#run(l:next_job['cmd'], l:next_job['open_qf'], l:next_job['err_fmt'])
    endif

    if a:ret_code != 0 || l:open_qf != 0
        silent copen
    else
        silent cwindow
    endif
endfunction

function! s:createJobBuf() abort
    const l:cursor_was_in_quickfix = getwininfo( win_getid() )[0]['quickfix']

    let s:job_bufid = bufadd( s:cmake4vim_buf )

    call setbufvar( s:job_bufid, "&buftype", 'nofile' )
    call setbufvar( s:job_bufid, 'list',        0 )
    call setbufvar( s:job_bufid, "&modifiable", 0 )
    call setbufvar( s:job_bufid, "&hidden",     0 )
    call setbufvar( s:job_bufid, "&swapfile",   0 )
    call setbufvar( s:job_bufid, "&wrap",       0 )
    call setbufvar( s:job_bufid, "&modifiable", 0 )

    call bufload( s:cmake4vim_buf )

    if l:cursor_was_in_quickfix
        silent execute 'keepalt edit ' . s:cmake4vim_buf
    else
        silent execute 'keepalt belowright 10split ' . s:cmake4vim_buf
    endif

    nmap <buffer> <C-c> :call utils#exec#job#stop()<CR>

    if !l:cursor_was_in_quickfix
        wincmd p
    endif

    return s:job_bufid
endfunction

" }}} Private functions "

function! utils#exec#job#getJobsPool() abort
    return s:cmake4vim_jobs_pool
endfunction

function! utils#exec#job#stop() abort
    if empty(s:cmake4vim_job)
        call s:closeBuffer()
        return
    endif

    let l:job = s:cmake4vim_job['job']
    if has('nvim')
        call jobstop(l:job)
    else
        call job_stop(l:job)
    endif

    call utils#common#Warning('Job is cancelled!')
endfunction

function! utils#exec#job#run(cmd, open_qf, err_fmt) abort
    " if there is a job or if the buffer is open, abort
    if !empty(s:cmake4vim_job) || s:job_bufid != -1
        call utils#common#Warning('Async execute is already running')
        if 'y' ==# inputdialog( 'Do you want to kill it? (y/n) ')
            call utils#exec#job#stop()
        endif
        return -1
    endif

    let l:outbufnr = s:createJobBuf()

    let s:cmake4vim_job = { 'cmd': a:cmd, 'open_qf': a:open_qf, 'err_fmt': a:err_fmt }

    if has('nvim')
        let l:job = jobstart(a:cmd, {
                    \ 'on_stdout': function('s:nVimOut'),
                    \ 'on_stderr': function('s:nVimOut'),
                    \ 'on_exit':   function('s:nVimExit'),
                    \ })
    else
        let l:cmd = has('win32') ? a:cmd : [&shell, '-c', a:cmd]
        let l:job = job_start(l:cmd, {
                    \ 'close_cb': function('s:vimClose'),
                    \ 'out_io' : 'buffer', 'out_buf' : l:outbufnr,
                    \ 'err_io' : 'buffer', 'err_buf' : l:outbufnr,
                    \ 'out_modifiable' : 0,
                    \ 'err_modifiable' : 0,
                    \ })
    endif

    let s:cmake4vim_job['job'] = l:job

    if !has('nvim')
       let s:cmake4vim_job['channel'] = job_getchannel(l:job)
    endif
    return l:job
endfunction

function! utils#exec#job#status() abort
    return s:cmake4vim_job
endfunction

function! utils#exec#job#append(cmd, open_qf, err_fmt) abort
    if !empty( s:cmake4vim_job )
        let s:cmake4vim_jobs_pool += [
                    \ {
                        \ 'cmd': a:cmd,
                        \ 'open_qf': a:open_qf,
                        \ 'err_fmt': a:err_fmt
                    \ }
                \ ]
        return 0
    endif
    return utils#exec#job#run(a:cmd, a:open_qf, a:err_fmt)
endfunction
