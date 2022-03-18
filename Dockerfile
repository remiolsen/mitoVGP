FROM mambaorg/micromamba:0.22.0

LABEL author="Remi-Andre Olsen" \
      maintainer="remi-andre.olsen@scilifelab.se"

USER root
RUN apt-get update && apt-get install -y git
COPY mitoVGP_mtDNApipe_env.yml /
RUN micromamba create -y -f /mitoVGP_mtDNApipe_env.yml
RUN cd /opt && git clone https://github.com/gf777/mitoVGP.git && chmod a+x mitoVGP/scripts/* && \
    apt-get clean
USER 1001
ENV PATH /opt/conda/envs/mitoVGP_pacbio/bin:/opt/mitoVGP/scripts:$PATH

