" ~/.config/nvim/init.vim — managed by chezmoi (dotfiles repo)
" Manual changes will be overwritten on next `chezmoi apply`.

" ----------------------------------------------------------------------
" Plugin manager: vim-plug
" vim-plug is installed by install.sh (curl into the nvim autoload dir).
" Inside nvim, run :PlugInstall to fetch plugins.
" ----------------------------------------------------------------------
call plug#begin(has('nvim') ? stdpath('data') . '/plugged' : '~/.vim/plugged')

Plug 'preservim/nerdtree'

call plug#end()

" ----------------------------------------------------------------------
" General
" ----------------------------------------------------------------------
set nocompatible                " Use vim defaults, not vi compatibility
filetype plugin indent on       " Enable filetype detection, plugins, indent
syntax on                       " Syntax highlighting

set encoding=utf-8
set scrolloff=5                 " Keep 5 lines visible above/below cursor

" Tabs and indentation
set tabstop=4                   " Width of a tab character
set softtabstop=4               " Width of a soft tab (spaces used for <Tab>)
set shiftwidth=4                " Width used for >> and << indentation
set expandtab                   " Convert tabs to spaces

" Search
set hlsearch                    " Highlight all matches of the last search
set incsearch                  " Incremental search: show match as you type
set ignorecase                 " Ignore case in search patterns
set smartcase                  " Override ignorecase when pattern has uppercase

" Buffer / session
set hidden                     " Allow hiding a buffer with unsaved changes without prompting

" Mouse
set mouse=a                    " Enable mouse in all modes

" ----------------------------------------------------------------------
" User Interface
" ----------------------------------------------------------------------
set number                      " Line numbers on
set relativenumber              " Relative line numbers (works with line numbers above)
set cursorline                  " Highlight current line

set wildmenu                    " Command-line completion menu
set wildignore+=*.o,*.obj,*.pyc,__pycache__

" ----------------------------------------------------------------------
" NERDTree
" ----------------------------------------------------------------------
" \n — toggle NERDTree
nnoremap <silent> <Leader>n :NERDTreeToggle<CR>

" Open NERDTree automatically when opening a directory
let g:NERDTreeAutoCenter=1
let g:NERDTreeShowHidden=1
let g:NERDTreeKeepWindowTogether=1