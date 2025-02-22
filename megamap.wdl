version 1.0

import "./hic.wdl"

workflow megamap {
    meta {
        version: "1.14.3"
        caper_docker: "encodedcc/hic-pipeline:1.14.3"
        caper_singularity: "docker://encodedcc/hic-pipeline:1.14.3"
    }

    input {
        Array[File] bams
        Array[File] hic_files
        File? restriction_sites
        File chrom_sizes
        String assembly_name = "undefined"

        # Parameters
        Int quality = 30
        Array[Int] create_hic_in_situ_resolutions = [2500000, 1000000, 500000, 250000, 100000, 50000, 25000, 10000, 5000, 2000, 1000, 500, 200, 100]
        Array[Int] create_hic_intact_resolutions = [2500000, 1000000, 500000, 250000, 100000, 50000, 25000, 10000, 5000, 2000, 1000, 500, 200, 100, 50, 20, 10]
        Boolean intact = true

        # Resource parameters
        Int? create_hic_num_cpus
        Int? create_hic_ram_gb
        Int? create_hic_juicer_tools_heap_size_gb
        Int? create_hic_disk_size_gb
        Int? add_norm_num_cpus
        Int? add_norm_ram_gb
        Int? add_norm_disk_size_gb
        Int? create_accessibility_track_ram_gb
        Int? create_accessibility_track_disk_size_gb

        # Pipeline images
        String docker = "encodedcc/hic-pipeline:1.14.3"
        String singularity = "docker://encodedcc/hic-pipeline:1.14.3"
        String delta_docker = "encodedcc/hic-pipeline:1.14.3_delta"
        String hiccups_docker = "encodedcc/hic-pipeline:1.14.3_hiccups"
    }

    RuntimeEnvironment runtime_environment = {
      "docker": docker,
      "singularity": singularity
    }

    RuntimeEnvironment hiccups_runtime_environment = {
      "docker": hiccups_docker,
      "singularity": singularity
    }

    RuntimeEnvironment delta_runtime_environment = {
      "docker": delta_docker,
      "singularity": singularity
    }

    String delta_models_path = if intact then "ultimate-models" else "beta-models"
    Array[Int] delta_resolutions = if intact then [5000, 2000, 1000] else [5000, 10000]
    Array[Int] create_hic_resolutions = if intact then create_hic_intact_resolutions else create_hic_in_situ_resolutions

    call hic.normalize_assembly_name as normalize_assembly_name { input:
        assembly_name = assembly_name,
        runtime_environment = runtime_environment,
    }

    call hic.merge as merge { input:
        bams = bams,
        runtime_environment = runtime_environment,
    }

    call hic.bam_to_pre as bam_to_pre { input:
        bam = merge.bam,
        quality = quality,
        runtime_environment = runtime_environment,
    }

    call hic.create_accessibility_track as accessibility { input:
        pre = bam_to_pre.pre,
        chrom_sizes = chrom_sizes,
        ram_gb = create_accessibility_track_ram_gb,
        disk_size_gb = create_accessibility_track_disk_size_gb,
        runtime_environment = runtime_environment,
    }

    call merge_stats_from_hic_files { input:
        hic_files = hic_files,
        runtime_environment = runtime_environment,
    }

    if (normalize_assembly_name.assembly_is_supported) {
        call hic.create_hic as create_hic { input:
            pre = bam_to_pre.pre,
            pre_index = bam_to_pre.index,
            restriction_sites = restriction_sites,
            quality = quality,
            stats = merge_stats_from_hic_files.merged_stats,
            stats_hists = merge_stats_from_hic_files.merged_stats_hists,
            resolutions = create_hic_resolutions,
            assembly_name = normalize_assembly_name.normalized_assembly_name,
            num_cpus = create_hic_num_cpus,
            ram_gb = create_hic_ram_gb,
            juicer_tools_heap_size_gb = create_hic_juicer_tools_heap_size_gb,
            disk_size_gb = create_hic_disk_size_gb,
            runtime_environment = runtime_environment,
        }
    }

    if (!normalize_assembly_name.assembly_is_supported) {
        call hic.create_hic as create_hic_with_chrom_sizes { input:
            pre = bam_to_pre.pre,
            pre_index = bam_to_pre.index,
            restriction_sites = restriction_sites,
            quality = quality,
            stats = merge_stats_from_hic_files.merged_stats,
            stats_hists = merge_stats_from_hic_files.merged_stats_hists,
            resolutions = create_hic_resolutions,
            assembly_name = assembly_name,
            num_cpus = create_hic_num_cpus,
            ram_gb = create_hic_ram_gb,
            juicer_tools_heap_size_gb = create_hic_juicer_tools_heap_size_gb,
            disk_size_gb = create_hic_disk_size_gb,
            chrsz =  chrom_sizes,
            runtime_environment = runtime_environment,
        }
    }

    File unnormalized_hic_file = select_first([
        if (defined(create_hic.output_hic))
        then create_hic.output_hic
        else create_hic_with_chrom_sizes.output_hic
    ])

    call hic.add_norm as add_norm { input:
        hic = unnormalized_hic_file,
        quality = quality,
        num_cpus = add_norm_num_cpus,
        ram_gb = add_norm_ram_gb,
        disk_size_gb = add_norm_disk_size_gb,
        runtime_environment = runtime_environment,
    }

    call hic.arrowhead as arrowhead { input:
        hic_file = add_norm.output_hic,
        quality = quality,
        runtime_environment = runtime_environment,
    }

    if (!intact) {
        call hic.hiccups { input:
            hic_file = add_norm.output_hic,
            quality = quality,
            runtime_environment = hiccups_runtime_environment,
        }
    }

    if (intact) {
        call hic.hiccups_2 { input:
            hic = add_norm.output_hic,
            quality = quality,
            runtime_environment = hiccups_runtime_environment,
        }

        call hic.localizer as localizer_intact { input:
            hic = add_norm.output_hic,
            loops = hiccups_2.merged_loops,
            quality = quality,
            runtime_environment = runtime_environment,
        }
    }

    call hic.create_eigenvector as create_eigenvector { input:
        hic_file = add_norm.output_hic,
        chrom_sizes = chrom_sizes,
        output_filename_suffix = "_" + quality,
        runtime_environment = runtime_environment,
    }

    call hic.create_eigenvector as create_eigenvector_10kb { input:
        hic_file = add_norm.output_hic,
        chrom_sizes = chrom_sizes,
        resolution = 10000,
        output_filename_suffix = "_" + quality,
        runtime_environment = runtime_environment,
    }

    call hic.delta as delta { input:
        hic = add_norm.output_hic,
        resolutions = delta_resolutions,
        models_path = delta_models_path,
        runtime_environment = delta_runtime_environment,
    }

    call hic.localizer as localizer_delta { input:
        hic = add_norm.output_hic,
        loops = delta.loops,
        runtime_environment = runtime_environment,
    }

    call hic.slice as slice_25kb { input:
        hic_file = add_norm.output_hic,
        resolution = 25000,
        runtime_environment = runtime_environment,
    }

    call hic.slice as slice_50kb { input:
        hic_file = add_norm.output_hic,
        resolution = 50000,
        runtime_environment = runtime_environment,
    }

    call hic.slice as slice_100kb { input:
        hic_file = add_norm.output_hic,
        resolution = 100000,
        runtime_environment = runtime_environment,
    }
}


task merge_stats_from_hic_files {
    input {
        Array[File] hic_files
        Int quality = 30
        RuntimeEnvironment runtime_environment
    }

    command <<<
        set -euo pipefail
        java \
            -jar \
            /opt/merge-stats.jar \
            ~{"inter_" + quality} \
            ~{sep=" " hic_files}
        python3 \
            "$(which jsonify_stats.py)" \
            inter_~{quality}.txt \
            stats_~{quality}.json
    >>>

    output {
        File merged_stats = "inter_~{quality}.txt"
        File merged_stats_hists = "inter_~{quality}_hists.m"
        File stats_json = "stats_~{quality}.json"
    }

    runtime {
        cpu : 1
        memory: "8 GB"
        disks: "local-disk 500 HDD"
        docker: runtime_environment.docker
        singularity: runtime_environment.singularity
    }
}
